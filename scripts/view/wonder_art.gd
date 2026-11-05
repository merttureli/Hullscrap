extends RefCounted
## The art of the ten race wonders (data/homelands.json `wonders`, docs/CONTENT.md section 24), drawn in code in the race's colours, each as big as a station:
## draw(cv, art, at, radius, clock, alpha) paints wonder `art` on canvas item `cv`, centred on `at`, about `radius` px across half. Visual only: its own fixed numbers.

const IDS: Array[String] = ["queen_ship", "star_forge", "singing_crystal", "bloom_world", "carved_face", "held_lake", "auction_ring", "scrap_cathedral", "barge_city", "concord_beacon"]


static func has_art(art: String) -> bool:
	return IDS.has(art)


## Paint wonder `art` at `at`. `clock` is seconds (the animation), `alpha` dims a wonder that is done.
static func draw(cv: CanvasItem, art: String, at: Vector2, r: float, clock: float, alpha := 1.0) -> void:
	match art:
		"queen_ship": _queen_ship(cv, at, r, clock, alpha)
		"star_forge": _star_forge(cv, at, r, clock, alpha)
		"singing_crystal": _singing_crystal(cv, at, r, clock, alpha)
		"bloom_world": _bloom_world(cv, at, r, clock, alpha)
		"carved_face": _carved_face(cv, at, r, clock, alpha)
		"held_lake": _held_lake(cv, at, r, clock, alpha)
		"auction_ring": _auction_ring(cv, at, r, clock, alpha)
		"scrap_cathedral": _scrap_cathedral(cv, at, r, clock, alpha)
		"barge_city": _barge_city(cv, at, r, clock, alpha)
		"concord_beacon": _concord_beacon(cv, at, r, clock, alpha)


static func _c(col: String, a: float) -> Color:
	return Color(col, a)


static func _glow(cv: CanvasItem, at: Vector2, r: float, col: Color, steps := 8) -> void:
	for i in steps:
		var k := float(i) / float(steps)
		cv.draw_circle(at, r * (1.0 - k * 0.85), Color(col, col.a * (0.05 + 0.1 * k)))


static func _poly(cv: CanvasItem, pts: PackedVector2Array, fill: Color, edge: Color, w: float) -> void:
	cv.draw_colored_polygon(pts, fill)
	var loop := pts.duplicate()
	loop.append(pts[0])
	cv.draw_polyline(loop, edge, w)


static func _rect(cv: CanvasItem, centre: Vector2, size: Vector2, ang: float, fill: Color, edge: Color, w: float) -> void:
	var h := size / 2.0
	var pts := PackedVector2Array()
	for v in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		pts.append(centre + v.rotated(ang))
	_poly(cv, pts, fill, edge, w)


## The dead queen-ship of the Kett: nine hulls end to end on a long curve, brood cells mostly dark, a few still beating green.
static func _queen_ship(cv: CanvasItem, at: Vector2, r: float, t: float, a: float) -> void:
	var seg := 9
	for i in seg:
		var k := float(i) / float(seg - 1) - 0.5
		var c := at + Vector2(k * r * 1.9, sin(k * 3.1) * r * 0.28)
		var ang := cos(k * 3.1) * 0.5
		var len := r * 0.24 * (1.0 + 0.5 * (0.5 - absf(k)))
		_rect(cv, c, Vector2(len, r * 0.2 * (1.0 + 0.6 * (0.5 - absf(k)))), ang, _c("#3a2812", a), _c("#c8913a", a), maxf(3.0, r * 0.012))
		for j in 5:
			var off := Vector2(((j - 2) * len * 0.17), (-1 if j % 2 == 0 else 1) * r * 0.03).rotated(ang)
			var live := (i * 7 + j * 3) % 11 == 0
			var beat := 0.5 + 0.5 * sin(t * 1.3 + i)
			cv.draw_circle(c + off, r * 0.022, _c("#8fe04a", a * (0.25 + 0.7 * beat)) if live else _c("#4a2a12", a))
	var head := at + Vector2(-0.95 * r, sin(-1.55) * r * 0.28)
	for s in [-1.0, 1.0]:
		cv.draw_arc(head + Vector2(-r * 0.12, s * r * 0.05), r * 0.2, PI * (0.5 if s > 0 else -0.5) - 0.9, PI * (0.5 if s > 0 else -0.5) + 0.9, 18, _c("#e0a23c", a), maxf(4.0, r * 0.018))
	cv.draw_circle(head, r * 0.03, _c("#8fe04a", a * (0.3 + 0.2 * sin(t * 0.7))))


## The Emberkin's star forge: a red giant, its corona, and a ring of forge-cities on its lip pouring slag into it.
static func _star_forge(cv: CanvasItem, at: Vector2, r: float, t: float, a: float) -> void:
	var sun := at + Vector2(r * 0.25, 0.0)
	_glow(cv, sun, r * 1.1, _c("#ff5a20", a), 10)
	cv.draw_circle(sun, r * 0.6, _c("#e8501a", a))
	cv.draw_circle(sun, r * 0.5, _c("#ff8a30", a))
	cv.draw_circle(sun, r * 0.3, _c("#ffd060", a))
	for k in 5:
		var s := t * 0.15 + k * 1.26
		cv.draw_arc(sun, r * (0.62 + 0.04 * sin(t + k)), s, s + 0.55, 12, _c("#ffb040", a * 0.8), maxf(4.0, r * 0.02))
	var n := 9
	for i in n:
		var ang := PI * 0.5 + i * TAU / float(n) * 0.55 + 0.35
		var p := sun + Vector2.from_angle(ang) * r * 0.92
		_rect(cv, p, Vector2(r * 0.17, r * 0.08), ang + PI / 2.0, _c("#3a1c0c", a), _c("#ffd060", a), maxf(3.0, r * 0.012))
		cv.draw_circle(p, r * 0.015, _c("#ff8030", a * (0.5 + 0.5 * sin(t * 3.0 + i))))
		if i % 2 == 0:
			var pts := PackedVector2Array()
			for s in 8:
				var u := float(s) / 7.0
				pts.append(p.lerp(sun + Vector2.from_angle(ang + 0.1) * r * 0.55, u) + Vector2.from_angle(ang + PI / 2.0) * sin(u * PI) * r * 0.09)
			cv.draw_polyline(pts, _c("#ffa040", a), maxf(3.0, r * 0.014))
			var hot := fmod(t * 0.35 + i * 0.13, 1.0)
			cv.draw_circle(pts[int(hot * 7.0)], r * 0.02, _c("#fff0b0", a))
	cv.draw_arc(sun, r * 0.92, PI * 0.3, PI * 1.65, 48, _c("#7a3a14", a), maxf(3.0, r * 0.01))


## The Singing Crystal of the Prismatic: a faceted moon of crystal, its note drawn as rings that leave it.
static func _singing_crystal(cv: CanvasItem, at: Vector2, r: float, t: float, a: float) -> void:
	_glow(cv, at, r * 1.15, _c("#43e6ff", a * 0.8), 8)
	var n := 9
	var rim := PackedVector2Array()
	for i in n:
		var ang := i * TAU / float(n) + 0.3
		rim.append(at + Vector2.from_angle(ang) * r * (0.62 + 0.14 * float((i * 5) % 3) / 2.0))
	for i in n:
		var tri := PackedVector2Array([at + Vector2(0.03, -0.05) * r, rim[i], rim[(i + 1) % n]])
		var shade := 0.35 + 0.5 * absf(sin(i * 1.7 + t * 0.2))
		cv.draw_colored_polygon(tri, Color(Color("#2a9ec0").lerp(Color("#e8ffff"), shade * 0.6), a))
		cv.draw_polyline(PackedVector2Array([at, rim[i]]), _c("#dfffff", a * 0.6), maxf(2.0, r * 0.006))
	var edge := rim.duplicate()
	edge.append(rim[0])
	cv.draw_polyline(edge, _c("#dfffff", a), maxf(3.0, r * 0.012))
	for k in 4:
		var u := fmod(t * 0.25 + k * 0.25, 1.0)
		cv.draw_arc(at, r * (0.85 + u * 0.9), 0.0, TAU, 64, _c("#43e6ff", a * (1.0 - u) * 0.7), maxf(3.0, r * 0.01))
	var g := t * 0.4
	cv.draw_circle(at + Vector2.from_angle(g) * r * 0.35, r * 0.04, _c("#ffffff", a * 0.9))


## The Sporelings' bloom-world: a green hulk-world with caps along its rim and a comet-tail of spores.
static func _bloom_world(cv: CanvasItem, at: Vector2, r: float, t: float, a: float) -> void:
	for i in 70:
		var u := float(i) / 70.0
		var drift := fmod(t * 0.04 + u, 1.0)
		var p := at + Vector2(r * 0.4 + drift * r * 1.3, sin(i * 12.9898) * r * (0.1 + 0.55 * drift))
		cv.draw_circle(p, r * 0.012 * (1.0 - drift * 0.5), _c("#d8e890", a * (1.0 - drift) * 0.8))
	_glow(cv, at, r * 0.9, _c("#b5c96a", a * 0.7), 6)
	cv.draw_circle(at, r * 0.55, _c("#2c4a1c", a))
	for i in 9:
		var p := at + Vector2.from_angle(i * 2.4) * r * (0.1 + 0.3 * float((i * 7) % 5) / 4.0)
		cv.draw_circle(p, r * (0.08 + 0.03 * (i % 3)), _c("#6a8a3a", a * 0.8))
	for i in 22:
		var ang := i * TAU / 22.0
		var p := at + Vector2.from_angle(ang) * r * 0.56
		var cap := r * (0.06 + 0.03 * float(i % 3))
		cv.draw_line(p, p + Vector2.from_angle(ang) * cap, _c("#8aa44a", a), maxf(3.0, r * 0.012))
		cv.draw_circle(p + Vector2.from_angle(ang) * cap, cap * 0.7, _c("#c8e070" if i % 4 else "#f2f0a0", a))
		if i % 5 == 0:
			cv.draw_circle(p + Vector2.from_angle(ang) * cap, cap * (0.3 + 0.2 * sin(t * 2.0 + i)), _c("#ffffd0", a * 0.8))


## The Basalt's carved face: a quarry-moon cut into a brow, two sockets lit by cutters' lamps, a nose and a mile-wide mouth, with scaffolds on it.
static func _carved_face(cv: CanvasItem, at: Vector2, r: float, t: float, a: float) -> void:
	cv.draw_circle(at, r * 0.7, _c("#5c544c", a))
	cv.draw_circle(at, r * 0.7, _c("#8a7f74", a * 0.25))
	cv.draw_arc(at, r * 0.7, 0.0, TAU, 64, _c("#a89c90", a), maxf(4.0, r * 0.014))
	var brow := PackedVector2Array([at + Vector2(-0.5, -0.22) * r, at + Vector2(-0.2, -0.3) * r, at + Vector2(0.0, -0.24) * r, at + Vector2(0.2, -0.3) * r, at + Vector2(0.5, -0.22) * r])
	cv.draw_polyline(brow, _c("#2e2a26", a), maxf(6.0, r * 0.03))
	for s in [-1.0, 1.0]:
		var e := at + Vector2(s * 0.27, -0.08) * r
		cv.draw_circle(e, r * 0.1, _c("#1a1714", a))
		cv.draw_circle(e + Vector2(0, r * 0.01), r * 0.04, _c("#ffd060", a * (0.6 + 0.3 * sin(t * 0.8 + s))))
	cv.draw_polyline(PackedVector2Array([at + Vector2(0.0, -0.18) * r, at + Vector2(-0.05, 0.14) * r, at + Vector2(0.09, 0.2) * r]), _c("#2e2a26", a), maxf(5.0, r * 0.024))
	var mouth := PackedVector2Array([at + Vector2(-0.34, 0.36) * r, at + Vector2(-0.1, 0.4) * r, at + Vector2(0.1, 0.4) * r, at + Vector2(0.34, 0.36) * r, at + Vector2(0.1, 0.45) * r, at + Vector2(-0.1, 0.45) * r])
	cv.draw_colored_polygon(mouth, _c("#1a1714", a))
	for i in 6:
		var x := -0.5 + i * 0.2
		cv.draw_line(at + Vector2(x, -0.55) * r, at + Vector2(x + 0.1, 0.55) * r, _c("#c8a060", a * 0.4), maxf(2.0, r * 0.006))
	for i in 12:
		var ang := i * 0.52 + 0.3
		cv.draw_circle(at + Vector2.from_angle(ang) * r * 0.72, r * 0.012, _c("#ffd060", a * (0.4 + 0.5 * sin(t * 2.0 + i))))


## The Mire's held lake: a lake of clear water in a ring of humming pylons, its spillings freezing into a fringe.
static func _held_lake(cv: CanvasItem, at: Vector2, r: float, t: float, a: float) -> void:
	_glow(cv, at, r, _c("#3fae8f", a * 0.6), 6)
	cv.draw_circle(at, r * 0.6, _c("#1f6f8a", a))
	cv.draw_circle(at, r * 0.5, _c("#3a9fba", a * 0.8))
	for k in 4:
		cv.draw_arc(at + Vector2(sin(t * 0.3 + k) * r * 0.06, 0), r * (0.12 + 0.11 * k), 0.0, TAU, 40, _c("#c8f4ff", a * 0.35), maxf(2.0, r * 0.007))
	var n := 8
	var pts := PackedVector2Array()
	for i in n:
		var ang := i * TAU / float(n) + PI / 8.0
		var p := at + Vector2.from_angle(ang) * r * 0.82
		pts.append(p)
		cv.draw_line(p, p + Vector2.from_angle(ang) * r * 0.1, _c("#7a8a96", a), maxf(4.0, r * 0.02))
		cv.draw_circle(p + Vector2.from_angle(ang) * r * 0.1, r * 0.03, _c("#7ae0c8", a * (0.6 + 0.4 * sin(t * 2.5 + i))))
	pts.append(pts[0])
	cv.draw_polyline(pts, _c("#7ae0c8", a * 0.5), maxf(2.0, r * 0.008))
	for i in 14:
		var ang := 0.4 + i * 0.19
		cv.draw_circle(at + Vector2.from_angle(ang) * r * (0.9 + 0.05 * (i % 3)), r * 0.014, _c("#e8ffff", a * 0.8))


## The Fenn's great auction ring: a ring of stalls hung with lanterns round a rostrum.
static func _auction_ring(cv: CanvasItem, at: Vector2, r: float, t: float, a: float) -> void:
	_glow(cv, at, r * 1.05, _c("#f2c744", a * 0.55), 6)
	cv.draw_circle(at, r * 0.78, _c("#2a2410", a))
	cv.draw_arc(at, r * 0.78, 0.0, TAU, 96, _c("#e8d050", a), maxf(6.0, r * 0.03))
	cv.draw_arc(at, r * 0.55, 0.0, TAU, 72, _c("#a89030", a), maxf(4.0, r * 0.016))
	for i in 24:
		var ang := i * TAU / 24.0
		var p := at + Vector2.from_angle(ang) * r * 0.78
		_rect(cv, p, Vector2(r * 0.08, r * 0.06), ang, _c("#6a4a20", a), _c("#f0e080", a), maxf(2.0, r * 0.006))
		var flick := 0.5 + 0.5 * sin(t * 4.0 + i * 1.7)
		cv.draw_circle(p + Vector2.from_angle(ang) * r * 0.08, r * 0.02, _c("#fff090", a * (0.5 + 0.5 * flick)))
	for i in 8:
		var ang := i * TAU / 8.0
		cv.draw_line(at + Vector2.from_angle(ang) * r * 0.1, at + Vector2.from_angle(ang) * r * 0.55, _c("#a89030", a * 0.7), maxf(2.0, r * 0.007))
	cv.draw_circle(at, r * 0.12, _c("#6a4a20", a))
	cv.draw_arc(at, r * 0.12, 0.0, TAU, 24, _c("#fff090", a), maxf(3.0, r * 0.01))
	var h := Vector2.from_angle(sin(t * 1.5) * 0.5 - 0.8)
	cv.draw_line(at, at + h * r * 0.2, _c("#f0e080", a), maxf(4.0, r * 0.014))


## The Gauntlings' scrap cathedral: wreck-hulls welded into a nave with spires and a rose window, lightning walking its buttresses.
static func _scrap_cathedral(cv: CanvasItem, at: Vector2, r: float, t: float, a: float) -> void:
	_rect(cv, at + Vector2(0, r * 0.15), Vector2(r * 1.3, r * 0.5), 0.0, _c("#3a2418", a), _c("#b06a4c", a), maxf(4.0, r * 0.014))
	for i in 7:
		var x := -0.6 + i * 0.2
		_rect(cv, at + Vector2(x, 0.2) * r, Vector2(r * 0.18, r * 0.4), 0.05 * float((i % 3) - 1), _c("#4a3020" if i % 2 else "#2e1c12", a), _c("#8a5a3c", a), maxf(2.0, r * 0.006))
	for s in [-1.0, 1.0]:
		var base := at + Vector2(s * 0.5, -0.12) * r
		_poly(cv, PackedVector2Array([base + Vector2(-0.1, 0.25) * r, base + Vector2(0.1, 0.25) * r, base + Vector2(0.07, -0.2) * r, base + Vector2(-0.07, -0.2) * r]), _c("#3a2418", a), _c("#b06a4c", a), maxf(3.0, r * 0.012))
		_poly(cv, PackedVector2Array([base + Vector2(-0.08, -0.2) * r, base + Vector2(0.08, -0.2) * r, base + Vector2(0, -0.62) * r]), _c("#4a3020", a), _c("#e0905a", a), maxf(3.0, r * 0.012))
	var rose := at + Vector2(0, -0.02) * r
	cv.draw_circle(rose, r * 0.17, _c("#1a0e08", a))
	for i in 12:
		var ang := i * TAU / 12.0
		cv.draw_circle(rose + Vector2.from_angle(ang) * r * 0.11, r * 0.032, Color.from_hsv(float(i) / 12.0 * 0.15 + 0.05, 0.6, 0.95, a))
	cv.draw_arc(rose, r * 0.17, 0.0, TAU, 32, _c("#e0905a", a), maxf(3.0, r * 0.01))
	for k in 3:
		var from := at + Vector2(-0.55 + k * 0.55, -0.28) * r
		var pts := PackedVector2Array([from])
		var seed_t := floorf(t * 6.0 + k * 3.0)
		for s in 6:
			pts.append(from + Vector2(sin((seed_t + s) * 12.9) * r * 0.06, (s + 1) * r * 0.07))
		cv.draw_polyline(pts, _c("#a8d8ff", a * (0.4 + 0.5 * fmod(t * 3.0 + k, 1.0))), maxf(2.0, r * 0.008))


## The Grundl's lashed barge-city: long barges side by side, cabled together, every window lit.
static func _barge_city(cv: CanvasItem, at: Vector2, r: float, t: float, a: float) -> void:
	_glow(cv, at, r * 1.0, _c("#8f9b5a", a * 0.4), 5)
	var rows := 6
	for i in rows:
		var y := (float(i) - (rows - 1) / 2.0) * r * 0.2
		var cols := 2 + (i * 3) % 2
		for j in cols:
			var x := (float(j) - (cols - 1) / 2.0) * r * 0.62 + (r * 0.07 if i % 2 else 0.0)
			var c := at + Vector2(x, y)
			_rect(cv, c, Vector2(r * 0.58, r * 0.15), 0.0, _c("#3a3f24", a), _c("#a8b46a", a), maxf(2.0, r * 0.007))
			for w in 7:
				var lit := (i * 5 + j * 3 + w) % 4 != 0
				cv.draw_rect(Rect2(c + Vector2(-r * 0.26 + w * r * 0.08, -r * 0.03), Vector2(r * 0.035, r * 0.04)), _c("#ffe8a0", a * (0.9 if lit else 0.15)))
			cv.draw_line(c + Vector2(r * 0.29, r * 0.075), c + Vector2(r * 0.33, r * 0.075), _c("#c8c8a0", a), maxf(2.0, r * 0.01))
	for i in 5:
		var y := (float(i) - 2.0 + 0.5) * r * 0.2
		cv.draw_line(at + Vector2(-r * 0.9, y), at + Vector2(r * 0.9, y), _c("#c8c8a0", a * 0.35), maxf(2.0, r * 0.006))
	for i in 10:
		var p := at + Vector2(-0.7 + i * 0.155, -0.72 if i % 2 else 0.72) * r
		var u := fmod(t * 0.2 + i * 0.1, 1.0)
		cv.draw_circle(p + Vector2(0, -u * r * 0.1) * (1.0 if p.y < at.y else -1.0), r * 0.018 * (1.0 - u), _c("#d8d8c0", a * (1.0 - u)))


## The first Concord beacon: a mile-high needle turning on its axis, a ring of old solar wings at its waist and a lamp that has never gone out.
static func _concord_beacon(cv: CanvasItem, at: Vector2, r: float, t: float, a: float) -> void:
	for k in 4:
		var u := fmod(t * 0.3 + k * 0.25, 1.0)
		cv.draw_arc(at + Vector2(0, -r * 0.62), r * (0.1 + u * 0.95), 0.0, TAU, 64, _c("#aaccff", a * (1.0 - u) * 0.6), maxf(3.0, r * 0.01))
	_poly(cv, PackedVector2Array([at + Vector2(-0.07, 0.72) * r, at + Vector2(0.07, 0.72) * r, at + Vector2(0.025, -0.6) * r, at + Vector2(-0.025, -0.6) * r]), _c("#d8e4f4", a), _c("#7aa4e8", a), maxf(3.0, r * 0.01))
	var spin := cos(t * 0.8)
	cv.draw_line(at + Vector2(spin * 0.02, 0.72) * r, at + Vector2(spin * 0.02, -0.55) * r, _c("#4a78c8", a * 0.6), maxf(2.0, r * 0.008))
	var w := at + Vector2(0, 0.1) * r
	for s in [-1.0, 1.0]:
		for k in 3:
			_rect(cv, w + Vector2(s * (0.18 + k * 0.16) * absf(spin) * r * 1.0, 0), Vector2(r * 0.13 * (0.4 + 0.6 * absf(spin)), r * 0.2), 0.0, _c("#2a3c6a", a), _c("#9ec0ff", a), maxf(2.0, r * 0.006))
	cv.draw_arc(w, r * 0.2, 0.0, TAU, 40, _c("#9ec0ff", a), maxf(3.0, r * 0.01))
	var lamp := at + Vector2(0, -0.64) * r
	_glow(cv, lamp, r * 0.25, _c("#ffffff", a), 6)
	cv.draw_circle(lamp, r * 0.04, _c("#ffffff", a))
	for s in 3:
		var ang := t * 0.9 + s * TAU / 3.0
		cv.draw_line(lamp, lamp + Vector2.from_angle(ang) * r * 0.5, _c("#ffffff", a * 0.35), maxf(2.0, r * 0.008))
	for i in 3:
		cv.draw_circle(at + Vector2((i - 1) * 0.06, 0.72) * r, r * 0.02, _c("#7aa4e8", a))
