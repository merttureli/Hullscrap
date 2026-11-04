extends RefCounted
## The art of the race rooms' fixtures (data/station_fixtures.json), drawn in code like the props': one `a_<fixture id>(cv, it)` each, called by station_decor.gd
## when the fixture has no `_art_<id>` of its own. `cv` is the decor node (the draw calls go to it), `it` the item of station_decor.gd `_fixture`: r (the
## rect), base (the fixture's colour in its race's tint), glow (its light, alpha 0 when it has none), dead, dir (the way it faces), lamp, id. Long fixtures may stand
## either way: `_p` and `_q` map a position along the long side (u) and across it (v) to the rect. Nothing here is logic.

const INK := Color(0.04, 0.05, 0.07)


## Has fixture `id` art here?
static func has_art(id: String) -> bool:
	return load("res://scripts/board/station_art.gd").has_method("a_" + id)


# --- helpers -----------------------------------------------------------------------------------------------------------

static func _p(r: Rect2, u: float, v: float) -> Vector2:
	return r.position + (Vector2(u * r.size.x, v * r.size.y) if r.size.x >= r.size.y else Vector2(v * r.size.x, u * r.size.y))


static func _q(r: Rect2, u0: float, v0: float, u1: float, v1: float) -> Rect2:
	var a := _p(r, u0, v0)
	var b := _p(r, u1, v1)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())


static func _lit(it: Dictionary, col: Color) -> Color:
	return col.darkened(0.65) if it["dead"] else col


static func _glow(it: Dictionary) -> Color:
	return _lit(it, Color(it["glow"], 1.0)) if Color(it["glow"]).a > 0.0 else Color(0.5, 0.5, 0.5)


## A solid body: its colour, a lit top edge, a dark foot, and the ink outline.
static func _box(cv: CanvasItem, r: Rect2, col: Color) -> void:
	cv.draw_rect(r, col)
	cv.draw_rect(Rect2(r.position, Vector2(r.size.x, minf(3.0, r.size.y * 0.25))), col.lightened(0.2))
	cv.draw_rect(Rect2(r.position + Vector2(0, r.size.y - minf(3.0, r.size.y * 0.25)), Vector2(r.size.x, minf(3.0, r.size.y * 0.25))), col.darkened(0.25))
	cv.draw_rect(r, INK, false, 2.0)


static func _ring(cv: CanvasItem, c: Vector2, rad: float, col: Color, w := 2.0) -> void:
	cv.draw_arc(c, rad, 0.0, TAU, 28, col, w, true)


static func _poly(cv: CanvasItem, pts: Array, col: Color, outline := true) -> void:
	var v := PackedVector2Array(pts)
	cv.draw_colored_polygon(v, col)
	if outline:
		cv.draw_polyline(v + PackedVector2Array([v[0]]), INK, 1.5)


static func _hex(c: Vector2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for q in 6:
		pts.append(c + Vector2.from_angle(TAU * float(q) / 6.0 + TAU / 12.0) * rad)
	return pts


static func _hexcell(cv: CanvasItem, c: Vector2, rad: float, fill: Color) -> void:
	var h := _hex(c, rad)
	cv.draw_colored_polygon(h, fill)
	cv.draw_polyline(h + PackedVector2Array([h[0]]), INK, 1.2)


## A repeatable 0..1 number from the fixture's id and a salt.
static func _rnd(it: Dictionary, salt: int) -> float:
	return float(posmod(int(it["id"]) * 7919 + salt * 104729 + int(it["id"]) * salt * 31, 1000)) / 1000.0


# --- human -------------------------------------------------------------------------------------------------------------

static func a_assembly_seats(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var base: Color = it["base"]
	cv.draw_rect(r, base.darkened(0.3))
	for k in 3:
		var s := _q(r, float(k) / 3.0 + 0.03, 0.12, float(k + 1) / 3.0 - 0.03, 0.88)
		cv.draw_rect(s, base.lightened(0.15))
		cv.draw_rect(_q(r, float(k) / 3.0 + 0.03, 0.12, float(k) / 3.0 + 0.12, 0.88), base.darkened(0.2))  # (the seat back)
		cv.draw_rect(s, INK, false, 1.2)
	cv.draw_rect(r, INK, false, 2.0)


static func a_speaker_podium(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	_box(cv, r, it["base"].darkened(0.1))
	var c := r.get_center()
	cv.draw_rect(Rect2(c - Vector2(8, 6), Vector2(16, 10)), Color(0.04, 0.05, 0.07))
	cv.draw_rect(Rect2(c - Vector2(6, 4), Vector2(12, 6)), _glow(it))
	cv.draw_line(c + Vector2(0, -6), c + Vector2(4, -11), Color(0.7, 0.7, 0.75), 1.5)  # (the microphone)
	cv.draw_circle(c + Vector2(4, -11), 1.8, Color(0.85, 0.85, 0.9))


static func a_flag_stand(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	cv.draw_circle(c + Vector2(0, 8), 7.0, Color(0.25, 0.26, 0.3))
	cv.draw_line(c + Vector2(-3, 8), c + Vector2(-3, -13), Color(0.75, 0.75, 0.8), 2.0)
	_poly(cv, [c + Vector2(-3, -13), c + Vector2(10, -10), c + Vector2(-3, -3)], Color(0.3, 0.5, 0.88) if not it["dead"] else Color(0.25, 0.3, 0.4), true)
	cv.draw_line(c + Vector2(-3, -9), c + Vector2(6, -9), Color(1, 1, 1, 0.8), 1.5)


static func a_drill_dummy(cv: CanvasItem, it: Dictionary) -> void:
	var c: Vector2 = it["r"].get_center()
	cv.draw_circle(c + Vector2(0, 8), 8.0, Color(0.28, 0.27, 0.25))
	cv.draw_line(c + Vector2(-10, -3), c + Vector2(10, -3), Color(0.55, 0.42, 0.25), 4.0)  # (the arms)
	cv.draw_line(c + Vector2(0, -8), c + Vector2(0, 9), Color(0.6, 0.46, 0.28), 5.0)
	cv.draw_circle(c + Vector2(0, -10), 5.0, Color(0.66, 0.54, 0.34))
	_ring(cv, c + Vector2(0, 0), 4.0, Color(0.85, 0.2, 0.15), 1.5)
	cv.draw_circle(c, 1.5, Color(0.85, 0.2, 0.15))


static func a_armour_rack(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	_box(cv, r, it["base"].darkened(0.15))
	for k in 3:
		var p := _p(r, 0.2 + 0.3 * float(k), 0.5)
		cv.draw_rect(Rect2(p - Vector2(5, 7), Vector2(10, 14)), Color(0.55, 0.6, 0.7).darkened(0.2 * float(k % 2)))  # (a breastplate)
		cv.draw_circle(p + Vector2(0, -8), 3.0, Color(0.7, 0.72, 0.78))  # (a helmet)
		cv.draw_rect(Rect2(p - Vector2(5, 7), Vector2(10, 14)), INK, false, 1.0)


static func a_target_lane(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(_q(r, 0.0, 0.2, 1.0, 0.8), Color(0.15, 0.17, 0.2, 0.9))
	for k in 5:
		var p := _p(r, 0.06 + 0.2 * float(k), 0.5)
		cv.draw_line(p + Vector2(0, -3), p + Vector2(0, 3), Color(1, 1, 1, 0.25), 1.5)
	var t := _p(r, 0.92, 0.5)  # (the target at the far end)
	_ring(cv, t, 9.0, _lit(it, Color(1.0, 0.35, 0.25)), 2.0)
	_ring(cv, t, 5.0, _lit(it, Color(1.0, 0.35, 0.25)), 2.0)
	cv.draw_circle(t, 2.0, _lit(it, Color(1.0, 0.7, 0.5)))


# --- basalt ------------------------------------------------------------------------------------------------------------

static func a_magma_channel(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, Color(0.16, 0.14, 0.13))
	var ch := _q(r, 0.04, 0.2, 0.96, 0.8)
	cv.draw_rect(ch, Color(0.07, 0.05, 0.04))
	if it["dead"]:  # (cooled to a crust)
		cv.draw_rect(ch.grow(-2.0), Color(0.22, 0.2, 0.19))
		cv.draw_line(ch.position + ch.size * Vector2(0.1, 0.3), ch.position + ch.size * Vector2(0.9, 0.7), Color(0.5, 0.15, 0.08), 1.5)
	else:
		cv.draw_rect(ch.grow(-2.0), Color(1.0, 0.4, 0.08, 0.95))
		var pts := PackedVector2Array()
		for q in 12:
			pts.append(_p(r, 0.08 + 0.84 * float(q) / 11.0, 0.5 + 0.12 * sin(float(q) * 1.7 + _rnd(it, 1) * 6.0)))
		cv.draw_polyline(pts, Color(1.0, 0.85, 0.35, 0.95), 2.5)
		for k in 4:
			cv.draw_circle(_p(r, 0.15 + 0.22 * float(k), 0.38 + 0.25 * float(k % 2)), 2.2, Color(1.0, 0.9, 0.5, 0.9))
	for k in 6:  # (basalt blocks on the banks)
		cv.draw_rect(Rect2(_p(r, 0.04 + 0.16 * float(k), 0.02 if k % 2 == 0 else 0.84), Vector2(7, 6)), Color(0.3, 0.29, 0.28))
	cv.draw_rect(r, INK, false, 2.0)


static func a_basalt_column(cv: CanvasItem, it: Dictionary) -> void:
	var c: Vector2 = it["r"].get_center()
	var h := _hex(c, 13.0)
	cv.draw_colored_polygon(h, it["base"].darkened(0.1))
	for q in 6:
		cv.draw_line(c, h[q], it["base"].lightened(0.2) if q % 2 == 0 else it["base"].darkened(0.35), 1.5)
	cv.draw_polyline(h + PackedVector2Array([h[0]]), INK, 2.0)


static func a_monolith(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var g := _glow(it)
	_box(cv, r, it["base"].darkened(0.2))
	var n := maxi(int(maxf(r.size.x, r.size.y) / 14.0), 3)
	for k in n:  # (runes cut into the face)
		var p := _p(r, (float(k) + 0.5) / float(n), 0.5)
		var s := 4.0 + 3.0 * _rnd(it, k)
		cv.draw_line(p + Vector2(-s, -s), p + Vector2(s, -s), g, 1.5)
		cv.draw_line(p + Vector2(0, -s), p + Vector2(0, s), g, 1.5)
		if k % 2 == 0:
			cv.draw_line(p + Vector2(-s, s), p + Vector2(s, 0), g, 1.5)


static func a_rune_tablet(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var g := _glow(it)
	cv.draw_rect(r, it["base"].darkened(0.3))
	for k in 3:
		var t := _q(r, float(k) / 3.0 + 0.04, 0.1, float(k + 1) / 3.0 - 0.04, 0.9)
		cv.draw_rect(t, it["base"].lightened(0.05))
		cv.draw_rect(t, INK, false, 1.2)
		var c := t.get_center()
		cv.draw_line(c + Vector2(-4, -4), c + Vector2(4, 4), g, 1.5)
		cv.draw_line(c + Vector2(4, -4), c + Vector2(-4, 4), g, 1.5)
	cv.draw_rect(r, INK, false, 2.0)


# --- emberkin ----------------------------------------------------------------------------------------------------------

static func a_great_hearth(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, it["base"].darkened(0.45))
	cv.draw_rect(r, INK, false, 2.0)
	var pit := _q(r, 0.08, 0.18, 0.92, 0.82)
	cv.draw_rect(pit, Color(0.06, 0.03, 0.03))
	if it["dead"]:
		cv.draw_rect(pit.grow(-3.0), Color(0.2, 0.18, 0.17))
		return
	cv.draw_rect(pit.grow(-3.0), Color(0.9, 0.3, 0.06, 0.95))
	for k in 5:  # (flames)
		var b := _p(r, 0.14 + 0.18 * float(k), 0.7)
		var hgt := 14.0 + 8.0 * _rnd(it, k)
		_poly(cv, [b + Vector2(-6, 0), b + Vector2(0, -hgt), b + Vector2(6, 0)], Color(1.0, 0.7, 0.15, 0.95), false)
		_poly(cv, [b + Vector2(-3, 0), b + Vector2(0, -hgt * 0.55), b + Vector2(3, 0)], Color(1.0, 0.95, 0.6), false)
	cv.draw_line(_p(r, 0.04, 0.12), _p(r, 0.96, 0.12), Color(0.25, 0.25, 0.28), 3.0)  # (the spit)


static func a_ember_bench(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, it["base"].darkened(0.3))
	for k in 5:
		cv.draw_rect(_q(r, 0.04 + 0.19 * float(k), 0.15, 0.04 + 0.19 * float(k) + 0.15, 0.85), it["base"])
	for k in 4:
		cv.draw_circle(_p(r, 0.2 + 0.2 * float(k), 0.5), 1.6, Color(1.0, 0.5, 0.15, 0.9) if not it["dead"] else Color(0.3, 0.2, 0.18))
	cv.draw_rect(r, INK, false, 2.0)


static func a_bellows(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var pts := [_p(r, 0.0, 0.1), _p(r, 0.8, 0.3), _p(r, 0.8, 0.7), _p(r, 0.0, 0.9)]
	_poly(cv, pts, Color(0.5, 0.33, 0.2), true)
	for k in 4:
		cv.draw_line(_p(r, 0.1 + 0.18 * float(k), 0.15 + 0.03 * float(k)), _p(r, 0.1 + 0.18 * float(k), 0.85 - 0.03 * float(k)), Color(0, 0, 0, 0.4), 1.5)
	cv.draw_line(_p(r, 0.8, 0.5), _p(r, 1.0, 0.5), Color(0.3, 0.3, 0.33), 3.0)  # (the nozzle)


# --- fenn --------------------------------------------------------------------------------------------------------------

static func a_auction_block(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) / 2.0
	cv.draw_circle(c, rad, it["base"].darkened(0.3))
	cv.draw_circle(c, rad * 0.75, it["base"])
	_ring(cv, c, rad * 0.75, _glow(it), 2.0)
	cv.draw_rect(Rect2(c + Vector2(-5, -3), Vector2(10, 6)), Color(0.35, 0.22, 0.12))  # (the gavel block)
	cv.draw_line(c + Vector2(-9, 8), c + Vector2(6, -2), Color(0.55, 0.38, 0.2), 3.0)
	cv.draw_rect(Rect2(c + Vector2(3, -6), Vector2(8, 5)), Color(0.5, 0.34, 0.18))
	_ring(cv, c, rad, INK, 2.0)


static func a_bidder_bench(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, it["base"].darkened(0.2))
	for k in 3:
		cv.draw_rect(_q(r, float(k) / 3.0 + 0.05, 0.15, float(k + 1) / 3.0 - 0.05, 0.85), it["base"].lightened(0.1))
		var p := _p(r, (float(k) + 0.5) / 3.0, 0.5)  # (a bidder's paddle)
		cv.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color.from_hsv(0.08 + 0.27 * float(k), 0.6, 0.9))
	cv.draw_rect(r, INK, false, 2.0)


static func a_tally_board(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	_box(cv, r, Color(0.14, 0.18, 0.15))
	var g := _glow(it)
	for k in 5:
		var y := 0.18 + 0.15 * float(k)
		cv.draw_line(_p(r, 0.06, y), _p(r, 0.06 + 0.55 * (0.4 + 0.6 * _rnd(it, k)), y), g, 2.0)
		cv.draw_line(_p(r, 0.82, y), _p(r, 0.94, y), g.darkened(0.3), 2.0)


static func a_junk_dynamo(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, Color(0.3, 0.27, 0.22))
	var plates := [Color(0.55, 0.4, 0.2), Color(0.4, 0.5, 0.55), Color(0.6, 0.55, 0.3), Color(0.5, 0.3, 0.25)]
	for k in 4:
		cv.draw_rect(_q(r, 0.02 + 0.24 * float(k), 0.05 if k % 2 == 0 else 0.55, 0.22 + 0.24 * float(k), 0.45 if k % 2 == 0 else 0.95), plates[k])
	var c := r.get_center()
	cv.draw_circle(c, minf(r.size.x, r.size.y) * 0.32, Color(0.12, 0.12, 0.14))
	cv.draw_circle(c, minf(r.size.x, r.size.y) * 0.22, _glow(it))
	for k in 6:
		cv.draw_line(c + Vector2.from_angle(TAU * float(k) / 6.0) * 7.0, c + Vector2.from_angle(TAU * float(k) / 6.0) * 13.0, Color(0.85, 0.85, 0.5), 1.5)
	cv.draw_line(r.position + Vector2(4, 4), c, Color(0.1, 0.1, 0.1), 2.0)  # (a cable and a patch)
	cv.draw_rect(r, INK, false, 2.0)


static func a_spare_parts_wall(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	_box(cv, r, it["base"].darkened(0.2))
	for k in 4:
		var p := _p(r, 0.12 + 0.25 * float(k), 0.5)
		if k % 2 == 0:
			_ring(cv, p, 5.0, Color(0.7, 0.7, 0.75), 2.0)
			cv.draw_circle(p, 1.5, Color(0.7, 0.7, 0.75))
		else:
			cv.draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), Color(0.7, 0.45, 0.25), 3.0)


# --- kett --------------------------------------------------------------------------------------------------------------

static func a_nectar_vat(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, Color(0.25, 0.2, 0.1))
	cv.draw_rect(r.grow(-3.0), _lit(it, Color(0.85, 0.6, 0.12)))
	var rad := minf(r.size.x, r.size.y) * 0.16
	for ix in int(r.size.x / (rad * 1.8)) - 1:
		for iy in int(r.size.y / (rad * 1.8)) - 1:
			var c := r.position + Vector2(rad * 1.6 + rad * 1.75 * float(ix) + (rad * 0.9 if iy % 2 == 1 else 0.0), rad * 1.5 + rad * 1.55 * float(iy))
			var h := _hex(c, rad)
			cv.draw_polyline(h + PackedVector2Array([h[0]]), Color(0.45, 0.28, 0.05, 0.8), 1.5)
	cv.draw_circle(r.get_center() + Vector2(-5, -4), 3.0, Color(1.0, 0.9, 0.5, 0.7))
	cv.draw_rect(r, INK, false, 2.0)


static func a_comb_cradle(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, it["base"].darkened(0.3))
	for k in 2:
		var c := _p(r, 0.27 + 0.46 * float(k), 0.5)
		_hexcell(cv, c, minf(r.size.x, r.size.y) * 0.4, it["base"].lightened(0.12))
		cv.draw_circle(c, 3.0, Color(0.95, 0.9, 0.7))  # (a grub)
	cv.draw_rect(r, INK, false, 2.0)


# --- mire --------------------------------------------------------------------------------------------------------------

static func a_marsh_pool(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, Color(0.18, 0.2, 0.17))
	cv.draw_rect(r.grow(-3.0), _lit(it, Color(0.2, 0.55, 0.45)))
	for k in 4:
		var c := r.position + r.size * Vector2(0.2 + 0.2 * float(k), 0.3 + 0.4 * float((k * 5) % 3) / 2.0)
		cv.draw_circle(c, 5.0, Color(0.25, 0.5, 0.2))  # (lily pads)
		cv.draw_line(c, c + Vector2(4, -2), Color(0.1, 0.25, 0.1), 1.0)
	for k in 3:
		_ring(cv, r.get_center() + Vector2(float(k - 1) * r.size.x * 0.2, r.size.y * 0.05), 5.0 + 3.0 * float(k), Color(1, 1, 1, 0.2), 1.5)
	if not it["dead"]:
		cv.draw_circle(r.position + r.size * Vector2(0.85, 0.2), 2.5, Color(it["glow"], 0.9))
	cv.draw_rect(r, INK, false, 2.0)


static func a_reed_clump(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	for k in 5:
		var b := r.position + r.size * Vector2(0.2 + 0.15 * float(k), 0.9)
		var t := b + Vector2((float(k) - 2.0) * 2.5, -16.0 - 4.0 * _rnd(it, k))
		cv.draw_line(b, t, Color(0.3, 0.55, 0.28) if not it["dead"] else Color(0.45, 0.4, 0.25), 2.0)
		if k % 2 == 0:
			cv.draw_line(t, t + Vector2(0, -5), Color(0.4, 0.25, 0.12), 3.0)  # (a cattail)


static func a_rain_curtain(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(_q(r, 0.0, 0.2, 0.06, 0.8), Color(0.45, 0.5, 0.5))
	cv.draw_rect(_q(r, 0.94, 0.2, 1.0, 0.8), Color(0.45, 0.5, 0.5))
	cv.draw_line(_p(r, 0.0, 0.5), _p(r, 1.0, 0.5), Color(0.5, 0.55, 0.55, 0.6), 2.0)
	if not it["dead"]:
		for k in 14:
			var p := _p(r, 0.08 + 0.065 * float(k), 0.25 + 0.5 * _rnd(it, k))
			cv.draw_line(p, p + Vector2(0, 5), Color(0.6, 0.85, 1.0, 0.7), 1.2)


static func a_cistern_vat(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) / 2.0
	cv.draw_circle(c, rad, it["base"].darkened(0.25))
	cv.draw_circle(c, rad * 0.78, _lit(it, Color(0.3, 0.6, 0.8)))
	_ring(cv, c, rad * 0.78, Color(0.7, 0.75, 0.8), 2.0)
	for k in 8:
		cv.draw_circle(c + Vector2.from_angle(TAU * float(k) / 8.0) * rad * 0.9, 1.3, Color(0.8, 0.8, 0.85))
	cv.draw_line(c + Vector2(-5, 0), c + Vector2(5, 0), Color(1, 1, 1, 0.45), 1.5)
	_ring(cv, c, rad, INK, 2.0)


# --- sporeling ---------------------------------------------------------------------------------------------------------

static func a_mycelium_mat(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var g := Color(it["glow"], 0.0) if it["dead"] else Color(it["glow"], 0.85)
	cv.draw_rect(r, Color(0.35, 0.5, 0.28, 0.45))
	for k in 7:
		var a := r.position + r.size * Vector2(_rnd(it, k), _rnd(it, k + 20))
		var b := r.position + r.size * Vector2(_rnd(it, k + 40), _rnd(it, k + 60))
		cv.draw_line(a, b, Color(0.8, 0.95, 0.65, 0.5), 1.2)
		cv.draw_circle(a, 2.0, g)
	cv.draw_rect(r, Color(0.2, 0.3, 0.15, 0.7), false, 1.5)


static func a_puffball_lamp(cv: CanvasItem, it: Dictionary) -> void:
	var c: Vector2 = it["r"].get_center()
	if not it["dead"]:
		cv.draw_circle(c, 14.0, Color(it["glow"], 0.18))
	cv.draw_circle(c, 9.0, Color(0.8, 0.88, 0.6) if not it["dead"] else Color(0.4, 0.45, 0.35))
	for k in 5:
		cv.draw_circle(c + Vector2.from_angle(TAU * float(k) / 5.0 + 0.5) * 4.5, 1.6, _lit(it, Color(it["glow"], 1.0)).darkened(0.1))
	cv.draw_circle(c + Vector2(-3, -3), 2.0, Color(1, 1, 1, 0.55))


# --- gauntling ---------------------------------------------------------------------------------------------------------

static func a_arc_coil(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) / 2.0
	var g := _glow(it)
	cv.draw_rect(r, Color(0.14, 0.15, 0.18))
	cv.draw_circle(c, rad * 0.85, Color(0.22, 0.24, 0.28))
	for k in 3:
		_ring(cv, c, rad * (0.7 - 0.2 * float(k)), Color(0.55, 0.58, 0.64) if k % 2 == 0 else g.darkened(0.2), 3.0)
	cv.draw_circle(c, rad * 0.14, g.lightened(0.5))
	if not it["dead"]:
		for k in 4:  # (arcs jumping out to the frame)
			var a := TAU * float(k) / 4.0 + 0.5 + _rnd(it, k)
			var pts := PackedVector2Array([c])
			for s in 4:
				pts.append(c + Vector2.from_angle(a + 0.25 * sin(float(s) * 2.0 + float(k))) * rad * (0.3 + 0.22 * float(s)))
			cv.draw_polyline(pts, Color(g, 0.9), 2.0)
	cv.draw_rect(r, INK, false, 2.0)


static func a_capacitor_bank(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	_box(cv, r, it["base"].darkened(0.1))
	for k in 3:
		var p := _p(r, 0.2 + 0.3 * float(k), 0.5)
		cv.draw_circle(p, 6.5, Color(0.2, 0.22, 0.27))
		_ring(cv, p, 6.5, _glow(it), 2.0)
		cv.draw_circle(p, 2.0, _glow(it))


static func a_scrap_heap(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var cols := [Color(0.42, 0.4, 0.38), Color(0.5, 0.33, 0.22), Color(0.3, 0.32, 0.36), Color(0.6, 0.55, 0.45)]
	for k in 9:
		var c := r.position + r.size * Vector2(0.12 + 0.76 * _rnd(it, k), 0.15 + 0.7 * _rnd(it, k + 9))
		var pts: Array = []
		for q in 5:
			pts.append(c + Vector2.from_angle(TAU * float(q) / 5.0 + _rnd(it, q + k)) * (6.0 + 6.0 * _rnd(it, q + k + 3)))
		_poly(cv, pts, cols[k % 4], true)
	cv.draw_line(r.position + r.size * Vector2(0.3, 0.2), r.position + r.size * Vector2(0.7, 0.8), Color(0.8, 0.8, 0.85), 1.5)


static func a_sorting_belt(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, Color(0.2, 0.21, 0.24))
	var belt := _q(r, 0.0, 0.2, 1.0, 0.8)
	cv.draw_rect(belt, Color(0.1, 0.1, 0.12))
	for k in 8:
		var p := _p(r, 0.07 + 0.12 * float(k), 0.5)
		cv.draw_line(p + Vector2(-2, -4), p + Vector2(2, 0), Color(0.8, 0.7, 0.2, 0.6), 1.5)
		cv.draw_line(p + Vector2(2, 0), p + Vector2(-2, 4), Color(0.8, 0.7, 0.2, 0.6), 1.5)
	for k in 3:  # (sorted bits on the belt)
		cv.draw_rect(Rect2(_p(r, 0.15 + 0.3 * float(k), 0.4) - Vector2(4, 4), Vector2(8, 8)), Color(0.55, 0.4, 0.3) if k % 2 == 0 else Color(0.5, 0.55, 0.6))
	cv.draw_rect(r, INK, false, 2.0)


# --- grundl ------------------------------------------------------------------------------------------------------------

static func a_ballast_weight(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) / 2.0
	var oct := PackedVector2Array()
	for q in 8:
		oct.append(c + Vector2.from_angle(TAU * float(q) / 8.0 + TAU / 16.0) * rad)
	cv.draw_colored_polygon(oct, it["base"])
	cv.draw_polyline(oct + PackedVector2Array([oct[0]]), INK, 2.0)
	_ring(cv, c, rad * 0.55, Color(0, 0, 0, 0.4), 2.0)
	_ring(cv, c, rad * 0.28, Color(0.7, 0.7, 0.72), 3.0)  # (the lifting eye)
	cv.draw_line(c + Vector2(-rad * 0.6, rad * 0.5), c + Vector2(rad * 0.6, rad * 0.5), Color(1, 1, 1, 0.2), 2.0)


static func a_chain_winch(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) / 2.0
	cv.draw_rect(r, it["base"].darkened(0.2))
	cv.draw_circle(c, rad * 0.8, Color(0.25, 0.25, 0.28))
	for k in 3:
		cv.draw_arc(c, rad * (0.7 - 0.17 * float(k)), 0.0, TAU, 20, Color(0.62, 0.62, 0.66), 3.0, true)  # (the wound chain)
	cv.draw_circle(c, rad * 0.14, Color(0.8, 0.8, 0.82))
	cv.draw_line(c, c + Vector2(rad * 0.9, rad * 0.3), Color(0.5, 0.5, 0.55), 3.0)
	cv.draw_circle(c + Vector2(rad * 0.9, rad * 0.3), 2.5, Color(0.8, 0.3, 0.2))
	cv.draw_rect(r, INK, false, 2.0)


static func a_great_cauldron(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) / 2.0
	cv.draw_rect(r, Color(0.16, 0.14, 0.14))
	cv.draw_circle(c, rad * 0.92, Color(0.18, 0.17, 0.18))
	cv.draw_circle(c, rad * 0.78, _lit(it, Color(0.62, 0.34, 0.14)))
	for k in 6:
		var p := c + Vector2.from_angle(TAU * float(k) / 6.0 + _rnd(it, 3)) * rad * (0.25 + 0.35 * _rnd(it, k))
		cv.draw_circle(p, 3.0 + 2.0 * _rnd(it, k + 7), Color(0.9, 0.6, 0.3, 0.8) if not it["dead"] else Color(0.35, 0.28, 0.22))
	_ring(cv, c, rad * 0.8, Color(0.55, 0.55, 0.6), 4.0)
	cv.draw_circle(c + Vector2(-rad * 0.92, 0), 3.0, Color(0.6, 0.6, 0.65))  # (the handles)
	cv.draw_circle(c + Vector2(rad * 0.92, 0), 3.0, Color(0.6, 0.6, 0.65))
	cv.draw_rect(r, INK, false, 2.0)


static func a_trestle_table(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, Color(0.35, 0.25, 0.16))
	cv.draw_rect(r.grow(-2.0), it["base"])
	for k in 5:
		var p := _p(r, 0.1 + 0.2 * float(k), 0.3 if k % 2 == 0 else 0.7)
		cv.draw_circle(p, 3.2, Color(0.9, 0.88, 0.82))
		cv.draw_circle(_p(r, 0.2 + 0.2 * float(k), 0.5), 2.0, Color(0.55, 0.3, 0.2))
	cv.draw_rect(r, INK, false, 2.0)


# --- prismatic ---------------------------------------------------------------------------------------------------------

static func a_focus_lens(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) / 2.0
	cv.draw_rect(r, Color(0.16, 0.14, 0.22))
	cv.draw_circle(c, rad * 0.85, Color(0.42, 0.38, 0.55))
	cv.draw_circle(c, rad * 0.68, Color(0.75, 0.88, 1.0, 0.85) if not it["dead"] else Color(0.35, 0.38, 0.45))
	if not it["dead"]:
		for k in 5:
			cv.draw_line(c, c + Vector2.from_angle(-0.9 + 0.45 * float(k)) * rad * 1.1, Color.from_hsv(0.55 + 0.1 * float(k), 0.5, 1.0, 0.7), 2.0)
		cv.draw_circle(c + Vector2(-rad * 0.25, -rad * 0.25), rad * 0.16, Color(1, 1, 1, 0.8))
	cv.draw_rect(r, INK, false, 2.0)


static func a_beam_rail(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var g := _glow(it)
	cv.draw_line(_p(r, 0.0, 0.5), _p(r, 1.0, 0.5), Color(0.4, 0.4, 0.5), 5.0)
	cv.draw_line(_p(r, 0.0, 0.5), _p(r, 1.0, 0.5), Color(g, 0.55), 3.0)
	for k in 3:
		var p := _p(r, 0.1 + 0.4 * float(k), 0.5)
		cv.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(5, 0), p + Vector2(0, 6), p + Vector2(-5, 0)]), Color(g, 0.95))


# --- vellum ------------------------------------------------------------------------------------------------------------

static func a_paper_stack(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	_box(cv, r, it["base"].darkened(0.25))
	for k in 6:  # (rolled scrolls on the shelves)
		for j in 2:
			var p := _p(r, 0.1 + 0.15 * float(k), 0.3 + 0.4 * float(j))
			cv.draw_circle(p, 3.6, Color(0.93, 0.9, 0.78) if (k + j) % 2 == 0 else Color(0.86, 0.8, 0.66))
			cv.draw_circle(p, 1.3, Color(0.5, 0.42, 0.3))


static func a_folding_desk(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, it["base"].darkened(0.3))
	cv.draw_rect(r.grow(-2.0), it["base"])
	for k in 3:  # (folded cranes and a sheet)
		var p := _p(r, 0.2 + 0.3 * float(k), 0.5)
		_poly(cv, [p + Vector2(-5, 3), p + Vector2(0, -6), p + Vector2(5, 3), p + Vector2(0, 1)], Color(0.97, 0.95, 0.88), true)
	cv.draw_rect(r, INK, false, 2.0)


static func a_paper_lantern(cv: CanvasItem, it: Dictionary) -> void:
	var c: Vector2 = it["r"].get_center()
	if not it["dead"]:
		cv.draw_circle(c, 15.0, Color(it["glow"], 0.16))
	cv.draw_circle(c, 9.0, Color(0.96, 0.9, 0.7) if not it["dead"] else Color(0.55, 0.52, 0.45))
	for k in 3:
		cv.draw_arc(c, 9.0, 0.0, TAU, 12, Color(0.6, 0.4, 0.25, 0.7), 1.0, true)
		cv.draw_line(c + Vector2(float(k - 1) * 4.0, -8), c + Vector2(float(k - 1) * 2.0, 8), Color(0.6, 0.4, 0.25, 0.6), 1.0)
	cv.draw_line(c + Vector2(0, -9), c + Vector2(0, -13), Color(0.3, 0.25, 0.2), 1.5)


# --- oorth -------------------------------------------------------------------------------------------------------------

static func a_still_basin(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) / 2.0
	cv.draw_rect(r, Color(0.14, 0.14, 0.2))
	cv.draw_circle(c, rad * 0.95, Color(0.3, 0.3, 0.42))
	cv.draw_circle(c, rad * 0.8, _lit(it, Color(0.25, 0.25, 0.6)))
	for k in 3:
		_ring(cv, c, rad * (0.25 + 0.2 * float(k)), Color(0.8, 0.78, 1.0, 0.3), 1.5)
	cv.draw_circle(c, 3.0, _lit(it, Color(0.85, 0.82, 1.0)))
	cv.draw_rect(r, INK, false, 2.0)


static func a_meditation_mat(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	cv.draw_rect(r.grow(-3.0), Color(it["base"], 0.85))
	cv.draw_rect(r.grow(-3.0), Color(0, 0, 0, 0.35), false, 1.5)
	cv.draw_circle(c, minf(r.size.x, r.size.y) * 0.28, it["base"].lightened(0.25))
	_ring(cv, c, minf(r.size.x, r.size.y) * 0.28, Color(0, 0, 0, 0.3), 1.2)


static func a_hood_statue(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	_box(cv, r, it["base"].darkened(0.2))
	var c := r.get_center()
	cv.draw_circle(c + Vector2(0, 4), 9.0, it["base"].lightened(0.1))  # (the shoulders)
	_poly(cv, [c + Vector2(-8, 2), c + Vector2(0, -12), c + Vector2(8, 2)], it["base"].lightened(0.25), true)  # (the hood)
	cv.draw_circle(c + Vector2(0, -2), 2.2, _lit(it, Color(0.7, 0.68, 1.0)))  # (the third eye)


# --- drakkin -----------------------------------------------------------------------------------------------------------

static func a_fighting_pit(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var sand := Color(0.72, 0.58, 0.38)
	cv.draw_rect(r, Color(0.28, 0.2, 0.15))
	cv.draw_rect(r.grow(-4.0), sand.darkened(0.15))
	cv.draw_rect(r.grow(-10.0), sand)
	for k in 7:  # (scuffs, and old blood)
		var p := r.position + r.size * Vector2(0.15 + 0.7 * _rnd(it, k), 0.2 + 0.6 * _rnd(it, k + 11))
		cv.draw_line(p, p + Vector2(8.0 * (_rnd(it, k + 5) - 0.5), 5.0 * (_rnd(it, k + 8) - 0.5)), Color(0.5, 0.38, 0.22, 0.6), 2.0)
		if k % 3 == 0:
			cv.draw_circle(p, 3.0, Color(0.45, 0.12, 0.1, 0.5))
	_ring(cv, c, minf(r.size.x, r.size.y) * 0.22, Color(0.45, 0.32, 0.2, 0.6), 2.0)
	for q in [r.position + Vector2(8, 8), Vector2(r.end.x - 8, r.position.y + 8), Vector2(r.position.x + 8, r.end.y - 8), r.end - Vector2(8, 8)]:  # (the corner stakes)
		cv.draw_circle(q, 4.0, Color(0.3, 0.28, 0.26))
		cv.draw_line(q, c, Color(0.35, 0.33, 0.3, 0.4), 1.0)
	cv.draw_rect(r, INK, false, 2.0)


static func a_trophy_wall(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	_box(cv, r, it["base"].darkened(0.2))
	for k in 3:
		var p := _p(r, (float(k) + 0.5) / 3.0, 0.5)
		cv.draw_circle(p, 6.0, Color(0.88, 0.84, 0.72))  # (a skull)
		cv.draw_circle(p + Vector2(-2.2, -1), 1.4, Color(0.1, 0.08, 0.08))
		cv.draw_circle(p + Vector2(2.2, -1), 1.4, Color(0.1, 0.08, 0.08))
		cv.draw_line(p + Vector2(-5, -5), p + Vector2(-9, -9), Color(0.85, 0.8, 0.65), 2.0)  # (horns)
		cv.draw_line(p + Vector2(5, -5), p + Vector2(9, -9), Color(0.85, 0.8, 0.65), 2.0)


static func a_spectator_bench(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	_slats(cv, it)
	for k in 4:  # (spined)
		var p := _p(r, 0.12 + 0.25 * float(k), 0.0)
		cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-3, 0), p + Vector2(0, -5), p + Vector2(3, 0)]), it["base"].lightened(0.3))


static func _slats(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, it["base"])
	cv.draw_rect(r, INK, false, 2.0)
	for k in int(maxf(r.size.x, r.size.y) / 8.0):
		cv.draw_line(_p(r, (5.0 + 8.0 * float(k)) / maxf(r.size.x, r.size.y), 0.1), _p(r, (5.0 + 8.0 * float(k)) / maxf(r.size.x, r.size.y), 0.9), Color(0, 0, 0, 0.3), 1.5)


# --- wisp --------------------------------------------------------------------------------------------------------------

static func a_current_loom(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, Color(0.08, 0.14, 0.18))
	var g := _glow(it)
	for k in 3:  # (ribbons of current)
		var pts := PackedVector2Array()
		for q in 14:
			pts.append(_p(r, 0.06 + 0.88 * float(q) / 13.0, 0.5 + 0.3 * sin(float(q) * 0.9 + float(k) * 2.1 + _rnd(it, 2) * 5.0) * (1.0 - 0.25 * float(k))))
		cv.draw_polyline(pts, Color(g, 0.9 - 0.2 * float(k)), 2.5 - 0.5 * float(k))
	cv.draw_rect(_q(r, 0.0, 0.0, 0.05, 1.0), Color(0.45, 0.55, 0.6))
	cv.draw_rect(_q(r, 0.95, 0.0, 1.0, 1.0), Color(0.45, 0.55, 0.6))
	cv.draw_rect(r, INK, false, 2.0)


static func a_static_column(cv: CanvasItem, it: Dictionary) -> void:
	var c: Vector2 = it["r"].get_center()
	var g := _glow(it)
	cv.draw_circle(c, 8.0, Color(0.2, 0.28, 0.32))
	cv.draw_circle(c, 5.0, Color(0.45, 0.58, 0.64))
	if not it["dead"]:
		cv.draw_circle(c, 13.0, Color(g, 0.14))
	for k in 3:
		cv.draw_arc(c, 6.0 + 2.5 * float(k), float(k) * 2.0, float(k) * 2.0 + 1.5, 6, Color(g, 0.9), 1.5, true)
	cv.draw_circle(c, 2.0, g.lightened(0.4))
	_ring(cv, c, 8.0, INK, 1.5)


# --- hullkin -----------------------------------------------------------------------------------------------------------

static func a_barnacle_bank(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, Color(0.3, 0.3, 0.28))
	for k in 14:
		var p := r.position + r.size * Vector2(0.06 + 0.88 * _rnd(it, k), 0.2 + 0.6 * _rnd(it, k + 30))
		var rad := 3.0 + 3.0 * _rnd(it, k + 60)
		cv.draw_circle(p, rad, Color(0.72, 0.72, 0.64))
		cv.draw_circle(p, rad * 0.45, Color(0.18, 0.18, 0.16))
	cv.draw_rect(r, INK, false, 2.0)


static func a_tide_basin(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, Color(0.3, 0.3, 0.28))
	cv.draw_rect(r.grow(-3.0), _lit(it, Color(0.2, 0.5, 0.62)))
	for k in 3:  # (shells and a starfish)
		var p := r.position + r.size * Vector2(0.2 + 0.3 * float(k), 0.35 + 0.3 * float(k % 2))
		cv.draw_circle(p, 4.5, Color(0.9, 0.78, 0.62))
		cv.draw_arc(p, 3.0, 0.0, PI, 6, Color(0.5, 0.35, 0.25), 1.2, true)
	for k in 2:
		_ring(cv, r.get_center() + Vector2(float(k) * 14.0 - 7.0, 0), 6.0, Color(1, 1, 1, 0.2), 1.5)
	cv.draw_rect(r, INK, false, 2.0)


# --- lantern -----------------------------------------------------------------------------------------------------------

static func a_lantern_tree(cv: CanvasItem, it: Dictionary) -> void:
	var c: Vector2 = it["r"].get_center()
	cv.draw_circle(c + Vector2(0, 9), 6.0, Color(0.25, 0.2, 0.16))
	cv.draw_line(c + Vector2(0, 9), c + Vector2(0, -8), Color(0.45, 0.33, 0.22), 3.0)
	var g := _glow(it)
	for k in 3:
		var a := c + Vector2(-8.0 + 8.0 * float(k), -2.0 - 4.0 * float(k % 2))
		cv.draw_line(c + Vector2(0, 2), a, Color(0.45, 0.33, 0.22), 2.0)
		if not it["dead"]:
			cv.draw_circle(a + Vector2(0, 4), 8.0, Color(g, 0.15))
		cv.draw_circle(a + Vector2(0, 4), 4.0, g)
		cv.draw_line(a + Vector2(0, 4), a, Color(0.3, 0.22, 0.15), 1.0)


static func a_perch_bar(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_line(_p(r, 0.04, 0.5), _p(r, 0.96, 0.5), it["base"].darkened(0.1), 5.0)
	cv.draw_line(_p(r, 0.0, 0.1), _p(r, 0.0, 0.9), it["base"].darkened(0.4), 4.0)
	cv.draw_line(_p(r, 1.0, 0.1), _p(r, 1.0, 0.9), it["base"].darkened(0.4), 4.0)
	for k in 3:  # (resting moths)
		var p := _p(r, 0.2 + 0.3 * float(k), 0.5)
		_poly(cv, [p + Vector2(-6, -4), p + Vector2(0, 0), p + Vector2(-6, 4)], Color(0.85, 0.78, 0.66), false)
		_poly(cv, [p + Vector2(6, -4), p + Vector2(0, 0), p + Vector2(6, 4)], Color(0.85, 0.78, 0.66), false)
		cv.draw_circle(p, 2.0, Color(0.4, 0.3, 0.22))


# --- revenant ----------------------------------------------------------------------------------------------------------

static func a_cairn(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var g := _glow(it)
	cv.draw_rect(r, Color(0.13, 0.15, 0.14))
	if not it["dead"]:
		cv.draw_circle(c, r.size.x * 0.5, Color(g, 0.12))
	var stones := [Vector2(-14, 8), Vector2(10, 10), Vector2(-2, 12), Vector2(-8, -2), Vector2(9, -1), Vector2(0, -12), Vector2(-3, 1)]
	for k in stones.size():
		var p: Vector2 = c + stones[k]
		var rad := 10.0 - 1.2 * float(k % 4)
		cv.draw_circle(p, rad, Color(0.38, 0.4, 0.4).darkened(0.1 * float(k % 3)))
		cv.draw_arc(p, rad, 0.0, TAU, 12, INK, 1.5, true)
	cv.draw_circle(c + Vector2(0, -14), 5.0, Color(0.85, 0.88, 0.8))  # (a skull on top)
	cv.draw_circle(c + Vector2(-1.8, -15), 1.2, INK)
	cv.draw_circle(c + Vector2(1.8, -15), 1.2, INK)
	cv.draw_circle(c + Vector2(0, -2), 2.5, g)


static func a_stitch_slab(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	_box(cv, r, it["base"])
	cv.draw_rect(r.grow(-5.0), Color(0.8, 0.8, 0.76, 0.85))  # (a sheet)
	for k in 5:
		var p := _p(r, 0.2 + 0.15 * float(k), 0.5)
		cv.draw_line(p + Vector2(-2, -4), p + Vector2(2, 4), Color(0.2, 0.3, 0.25), 1.5)
		cv.draw_line(p + Vector2(2, -4), p + Vector2(-2, 4), Color(0.2, 0.3, 0.25), 1.5)
	cv.draw_line(_p(r, 0.12, 0.5), _p(r, 0.88, 0.5), Color(0.2, 0.3, 0.25), 1.0)


# --- choir -------------------------------------------------------------------------------------------------------------

static func a_singing_bowl(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) / 2.0
	var g := _glow(it)
	cv.draw_rect(r, Color(0.2, 0.15, 0.22))
	cv.draw_circle(c, rad * 0.9, it["base"].darkened(0.3))
	cv.draw_circle(c, rad * 0.72, it["base"])
	cv.draw_circle(c, rad * 0.5, g.darkened(0.2) if not it["dead"] else Color(0.3, 0.26, 0.32))
	for k in 3:
		cv.draw_arc(c, rad * (0.3 + 0.2 * float(k)), -0.7, 0.7, 6, Color(1, 1, 1, 0.5 - 0.12 * float(k)), 1.5, true)
		cv.draw_arc(c, rad * (0.3 + 0.2 * float(k)), PI - 0.7, PI + 0.7, 6, Color(1, 1, 1, 0.5 - 0.12 * float(k)), 1.5, true)
	_ring(cv, c, rad * 0.9, INK, 2.0)


static func a_choir_stall(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, it["base"].darkened(0.3))
	for k in 3:
		var s := _q(r, float(k) / 3.0 + 0.03, 0.1, float(k + 1) / 3.0 - 0.03, 0.9)
		cv.draw_rect(s, it["base"])
		cv.draw_rect(_q(r, float(k) / 3.0 + 0.1, 0.18, float(k + 1) / 3.0 - 0.1, 0.45), Color(0.92, 0.9, 0.85))  # (a score)
		cv.draw_rect(s, INK, false, 1.2)
	cv.draw_rect(r, INK, false, 2.0)


# --- rattler -----------------------------------------------------------------------------------------------------------

static func a_junk_nest(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	cv.draw_circle(c, minf(r.size.x, r.size.y) * 0.46, Color(0.28, 0.24, 0.2))
	for k in 16:  # (wire and twigs woven round)
		var a := TAU * float(k) / 16.0
		cv.draw_line(c + Vector2.from_angle(a) * 8.0, c + Vector2.from_angle(a + 0.7 + _rnd(it, k)) * (15.0 + 4.0 * _rnd(it, k + 9)), Color(0.55, 0.5, 0.42), 1.5)
	cv.draw_circle(c, 7.0, Color(0.16, 0.14, 0.12))
	for k in 4:  # (the hoard)
		var p := c + Vector2.from_angle(float(k) * 1.7 + _rnd(it, 3)) * 3.5
		cv.draw_circle(p, 1.8, [Color(0.95, 0.8, 0.3), Color(0.5, 0.8, 0.95), Color(0.95, 0.45, 0.35), Color(0.85, 0.85, 0.9)][k])


static func a_gadget_bench(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, it["base"].darkened(0.3))
	cv.draw_rect(r.grow(-2.0), it["base"])
	var sc := _q(r, 0.06, 0.15, 0.3, 0.85)
	cv.draw_rect(sc, Color(0.04, 0.05, 0.06))
	cv.draw_rect(sc.grow(-1.5), _glow(it))
	cv.draw_line(_p(r, 0.4, 0.3), _p(r, 0.6, 0.7), Color(0.7, 0.7, 0.75), 2.0)  # (a spanner)
	cv.draw_circle(_p(r, 0.4, 0.3), 2.5, Color(0.7, 0.7, 0.75))
	cv.draw_rect(Rect2(_p(r, 0.72, 0.4) - Vector2(4, 3), Vector2(8, 6)), Color(0.5, 0.3, 0.25))
	cv.draw_line(_p(r, 0.3, 0.8), _p(r, 0.72, 0.5), Color(0.1, 0.1, 0.1), 1.5)
	cv.draw_rect(r, INK, false, 2.0)


# --- tessellate --------------------------------------------------------------------------------------------------------

static func a_reform_cradle(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var g := _glow(it)
	cv.draw_rect(r, Color(0.1, 0.16, 0.15))
	var n := 5
	var cell := minf(r.size.x, r.size.y) / float(n) * 0.9
	for ix in n:
		for iy in n:
			var p := r.position + r.size * 0.5 - Vector2(cell, cell) * float(n) / 2.0 + Vector2(cell * float(ix), cell * float(iy))
			var on := (ix + iy * 2 + int(it["id"])) % 3 != 0
			cv.draw_rect(Rect2(p + Vector2(1, 1), Vector2(cell - 2, cell - 2)), g if on else g.darkened(0.55))
	cv.draw_rect(r, INK, false, 2.0)


static func a_circuit_column(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var g := _glow(it)
	_box(cv, r, it["base"].darkened(0.3))
	for k in 3:  # (traces and nodes)
		var a := _p(r, 0.12, 0.25 + 0.25 * float(k))
		var b := _p(r, 0.88, 0.35 + 0.25 * float(k % 2))
		cv.draw_polyline(PackedVector2Array([a, Vector2(a.x, b.y), b]), Color(g, 0.8), 1.5)
		cv.draw_circle(b, 2.2, g)


# --- sable -------------------------------------------------------------------------------------------------------------

static func a_boarding_pod(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var g := _glow(it)
	cv.draw_rect(r, Color(0.13, 0.14, 0.18))
	var pts: Array = [_p(r, 0.04, 0.2), _p(r, 0.7, 0.08), _p(r, 0.97, 0.5), _p(r, 0.7, 0.92), _p(r, 0.04, 0.8)]
	_poly(cv, pts, it["base"], true)
	cv.draw_rect(_q(r, 0.42, 0.3, 0.68, 0.7), Color(0.2, 0.3, 0.4) if it["dead"] else Color(0.5, 0.75, 0.95, 0.9))  # (the port)
	cv.draw_line(_p(r, 0.1, 0.5), _p(r, 0.36, 0.5), Color(0, 0, 0, 0.4), 2.0)
	cv.draw_line(_p(r, 0.97, 0.5), _p(r, 1.04, 0.5), Color(0.55, 0.55, 0.6), 3.0)  # (the cutter arm)
	cv.draw_circle(_p(r, 1.02, 0.5), 3.0, g)
	cv.draw_line(_p(r, 0.2, 0.12), _p(r, 0.2, 0.0), Color(0.6, 0.6, 0.65), 2.0)  # (a grapple)


static func a_torch_rack(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	_box(cv, r, it["base"])
	var g := _glow(it)
	for k in 3:
		var p := _p(r, 0.2 + 0.3 * float(k), 0.5)
		cv.draw_rect(Rect2(p - Vector2(2, 6), Vector2(4, 12)), Color(0.7, 0.7, 0.75))
		cv.draw_circle(p + Vector2(0, -7), 3.0, g)


# --- quillback ---------------------------------------------------------------------------------------------------------

static func a_list_strip(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, Color(0.5, 0.42, 0.3))
	cv.draw_rect(r.grow(-5.0), it["base"])
	cv.draw_line(_p(r, 0.5, 0.1), _p(r, 0.5, 0.9), Color(1, 1, 1, 0.5), 2.0)  # (the centre line)
	cv.draw_line(_p(r, 0.14, 0.2), _p(r, 0.14, 0.8), Color(1, 1, 1, 0.4), 2.0)
	cv.draw_line(_p(r, 0.86, 0.2), _p(r, 0.86, 0.8), Color(1, 1, 1, 0.4), 2.0)
	for k in 8:  # (the rail posts)
		cv.draw_circle(_p(r, 0.03 + 0.134 * float(k), 0.04), 2.2, Color(0.35, 0.28, 0.2))
		cv.draw_circle(_p(r, 0.03 + 0.134 * float(k), 0.96), 2.2, Color(0.35, 0.28, 0.2))
	cv.draw_rect(r, INK, false, 2.0)


static func a_quill_rack(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	_box(cv, r, it["base"].darkened(0.1))
	for k in 5:  # (long spined lances)
		var a := _p(r, 0.12 + 0.19 * float(k), 0.8)
		cv.draw_line(a, _p(r, 0.14 + 0.19 * float(k), 0.1), Color(0.78, 0.72, 0.55), 2.0)
		cv.draw_circle(_p(r, 0.14 + 0.19 * float(k), 0.1), 1.8, Color(0.9, 0.9, 0.85))


# --- kite --------------------------------------------------------------------------------------------------------------

static func a_tether_web(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var g := Color(it["glow"], 0.0) if it["dead"] else Color(it["glow"], 0.8)
	var col := Color(it["base"], 0.7)
	for k in 7:
		var t := float(k) / 6.0
		cv.draw_line(r.position + Vector2(r.size.x * t, 0), r.position + Vector2(r.size.x * (1.0 - t), r.size.y), col, 1.2)
		cv.draw_line(r.position + Vector2(0, r.size.y * t), r.position + Vector2(r.size.x, r.size.y * (1.0 - t)), col, 1.2)
	for k in 4:
		cv.draw_circle(r.position + r.size * Vector2(0.2 + 0.2 * float(k), 0.3 + 0.4 * _rnd(it, k)), 2.2, g)
	for q in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		cv.draw_circle(q, 4.0, Color(0.45, 0.4, 0.6))


static func a_grip_post(cv: CanvasItem, it: Dictionary) -> void:
	var c: Vector2 = it["r"].get_center()
	cv.draw_circle(c, 9.0, Color(0.25, 0.22, 0.34))
	cv.draw_circle(c, 5.0, it["base"])
	_ring(cv, c, 10.0, it["base"].lightened(0.3), 2.5)
	cv.draw_circle(c + Vector2(-2, -2), 1.8, Color(1, 1, 1, 0.5))


# --- warden-frame ------------------------------------------------------------------------------------------------------

static func a_optic_cradle(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) * 0.4
	var g := _glow(it)
	cv.draw_rect(r, Color(0.12, 0.17, 0.2))
	cv.draw_rect(_q(r, 0.0, 0.0, 1.0, 0.12), Color(0.35, 0.45, 0.5))  # (the frame rails)
	cv.draw_rect(_q(r, 0.0, 0.88, 1.0, 1.0), Color(0.35, 0.45, 0.5))
	cv.draw_circle(c, rad, Color(0.06, 0.08, 0.1))
	cv.draw_circle(c, rad * 0.75, g.darkened(0.35) if not it["dead"] else Color(0.15, 0.2, 0.22))
	cv.draw_circle(c, rad * 0.4, g)
	cv.draw_circle(c, rad * 0.16, Color(0.02, 0.04, 0.05))
	cv.draw_line(c - Vector2(rad, 0), c + Vector2(rad, 0), Color(g, 0.5), 1.0)
	cv.draw_line(c - Vector2(0, rad), c + Vector2(0, rad), Color(g, 0.5), 1.0)
	_ring(cv, c, rad, INK, 2.0)
	cv.draw_rect(r, INK, false, 2.0)


static func a_gantry_arm(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var g := _glow(it)
	cv.draw_line(_p(r, 0.0, 0.2), _p(r, 1.0, 0.2), Color(0.4, 0.5, 0.55), 4.0)  # (the rail)
	var a := _p(r, 0.2, 0.2)
	var b := _p(r, 0.45, 0.65)
	var c := _p(r, 0.75, 0.5)
	cv.draw_polyline(PackedVector2Array([a, b, c]), Color(0.55, 0.65, 0.7), 4.0)
	for q in [a, b, c]:
		cv.draw_circle(q, 3.0, Color(0.25, 0.3, 0.34))
	cv.draw_circle(c, 2.0, g)


# --- murrow ------------------------------------------------------------------------------------------------------------

static func a_rock_face(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var pts: Array = [r.position + Vector2(0, r.size.y)]
	for k in 9:
		pts.append(r.position + Vector2(r.size.x * float(k) / 8.0, r.size.y * (0.08 + 0.35 * _rnd(it, k))))
	pts.append(r.end)
	_poly(cv, pts, it["base"].darkened(0.1), true)
	for k in 3:  # (ore glints)
		var p := r.position + r.size * Vector2(0.2 + 0.3 * float(k), 0.55 + 0.2 * _rnd(it, k + 5))
		cv.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -4), p + Vector2(3, 0), p + Vector2(0, 4), p + Vector2(-3, 0)]), [Color(0.95, 0.8, 0.3), Color(0.55, 0.85, 0.95), Color(0.9, 0.55, 0.3)][k])


static func a_ore_cart(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	_box(cv, r, it["base"].darkened(0.1))
	for k in 5:
		cv.draw_circle(_p(r, 0.15 + 0.17 * float(k), 0.3 + 0.4 * _rnd(it, k)), 4.5, Color(0.35, 0.33, 0.3) if k % 2 == 0 else Color(0.5, 0.45, 0.4))
	cv.draw_circle(_p(r, 0.5, 0.45), 2.0, Color(0.95, 0.8, 0.3))
	for q in [_p(r, 0.2, 0.0), _p(r, 0.8, 0.0), _p(r, 0.2, 1.0), _p(r, 0.8, 1.0)]:
		cv.draw_circle(q, 2.5, Color(0.12, 0.12, 0.14))


static func a_drill_rig(cv: CanvasItem, it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	cv.draw_rect(r, it["base"].darkened(0.3))
	var head := _q(r, 0.0, 0.1, 0.5, 0.9)
	var c := head.get_center()
	var rad := minf(head.size.x, head.size.y) * 0.5
	cv.draw_circle(c, rad, Color(0.3, 0.3, 0.32))
	for k in 8:
		var a := TAU * float(k) / 8.0
		_poly(cv, [c + Vector2.from_angle(a - 0.2) * rad, c + Vector2.from_angle(a) * (rad + 5.0), c + Vector2.from_angle(a + 0.2) * rad], Color(0.7, 0.7, 0.74), false)
	cv.draw_circle(c, rad * 0.35, Color(0.55, 0.55, 0.6))
	cv.draw_rect(_q(r, 0.5, 0.2, 1.0, 0.8), it["base"])
	cv.draw_circle(_p(r, 0.85, 0.4), 3.0, _glow(it))
	cv.draw_line(_p(r, 0.55, 0.3), _p(r, 0.95, 0.3), Color(0, 0, 0, 0.4), 1.5)
	cv.draw_rect(r, INK, false, 2.0)
