extends Node2D
## What a module station's windows look out on (site.backdrop, station_gen.gd _backdrop): a planet or a gas giant drawn behind the station, over the
## sector's own sky (the starfield and its nebula stay up while aboard). It lives on a canvas layer of its own under the site, so the dark of the site
## (board_view.gd's CanvasModulate) does not touch it: space is as bright through a window as it is outside. Screen space, with parallax: the body sits
## past the windows it was picked for (`at`, `dir`) and drifts against the camera at PARALLAX of the station's speed, so it reads as far away.
## The body is painted once into a texture (TEX px across): a lit sphere with noise land and seas, or bands for a gas giant (and a ring), and a rim of air.

const PATH := "res://data/station_modules.json"
const CELL := 32.0
const TEX := 384
const PARALLAX := 0.35

var spec := {}  ## site.backdrop: {kind, palette, radius (screen px), dir, at (cells), seed, ring, tilt}
var _tex: ImageTexture
var _rocks: Array = []  ## an asteroid field's rocks: [{off (x the radius), pts (x the radius), par, col, spin}]
var _moons: Array = []  ## a gas giant's moons: [{ang, dist (x the radius), size (x the radius), tex}]
var _clock := 0.0
var _glow := Color.WHITE
var _ring_col := Color(1, 1, 1, 0.3)


## Show the body of `p_spec` (the colours come from data/station_modules.json backdrop).
func setup(p_spec: Dictionary) -> void:
	spec = p_spec
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # (drawn far bigger than painted: smooth, not pixels)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))["backdrop"]
	var kc: Dictionary = cfg[str(spec["kind"])]
	var pal: Array = kc["palettes"][int(spec["palette"]) % kc["palettes"].size()]
	_glow = Color(str(kc.get("glow", "#8ac8ff")))
	_ring_col = Color(Color(str(pal[1])), 0.32)
	var kind := str(spec["kind"])
	var cols: Array = pal.map(func(c): return Color(str(c)))
	_rocks = []
	_moons = []
	_tex = null
	var r := RandomNumberGenerator.new()
	r.seed = int(spec["seed"])
	match kind:
		"nebula":
			_tex = ImageTexture.create_from_image(paint_nebula(cols, int(spec["seed"])))
		"asteroid_field":
			for i in 34:
				var pts := PackedVector2Array()
				var sides := r.randi_range(6, 9)
				var size := r.randf_range(0.02, 0.12) * pow(r.randf(), 2.0) * 3.0 + 0.012
				for k in sides:
					var a := TAU * float(k) / float(sides)
					pts.append(Vector2(cos(a), sin(a)) * size * r.randf_range(0.7, 1.15))
				_rocks.append({"off": Vector2(r.randf_range(-1.4, 1.4), r.randf_range(-0.5, 0.5)), "pts": pts, "par": r.randf_range(0.7, 1.4), "col": cols[r.randi() % cols.size()], "spin": r.randf_range(-0.1, 0.1)})
		"distant_station":
			pass
		_:
			_tex = ImageTexture.create_from_image(paint("planet" if kind == "planet" else "gas_giant", cols, int(spec["seed"]), float(spec.get("tilt", 0.0))))
			if kind == "gas_moons":
				for i in int(spec.get("moons", 2)):
					_moons.append({"ang": r.randf_range(0.0, TAU), "dist": r.randf_range(1.35, 2.3), "size": r.randf_range(0.06, 0.16), "tex": ImageTexture.create_from_image(paint("planet", [cols[r.randi() % cols.size()], cols[r.randi() % cols.size()], Color(0.9, 0.92, 0.95)], r.randi(), 0.0))})
	queue_redraw()


func _process(dt: float) -> void:
	_clock += dt
	queue_redraw()


## The middle of the body on screen: past the windows it was picked for, moving against the camera at PARALLAX.
func centre() -> Vector2:
	var vp := get_viewport_rect().size
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	var cam_pos := cam.get_screen_center_position() if cam != null else Vector2.ZERO
	var zoom := cam.zoom.x if cam != null else 1.0
	var r := float(spec.get("radius", 360.0))
	var dir: Vector2 = spec.get("dir", Vector2.UP)
	return vp / 2.0 + (spec.get("at", Vector2.ZERO) * CELL - cam_pos) * zoom * PARALLAX + dir * (r * 0.85 + 60.0)


func _draw() -> void:
	var r := float(spec.get("radius", 360.0))
	var c := centre()
	var kind := str(spec.get("kind", "planet"))
	if kind == "nebula":
		if _tex != null:
			draw_texture_rect(_tex, Rect2(c - Vector2(r, r) * 1.7, Vector2(r, r) * 3.4), false)
		return
	if kind == "asteroid_field":
		_draw_rocks(c, r)
		return
	if kind == "distant_station":
		_draw_station(c, r)
		return
	if _tex == null:
		return
	var tilt := float(spec.get("tilt", 0.0))
	if bool(spec.get("ring", false)):
		_ring(c, r, tilt, true)
	for k in 6:  # the rim of air, a few soft rings
		draw_circle(c, r * (1.0 + 0.012 * float(k + 1)), Color(_glow, 0.05))
	draw_texture_rect(_tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
	if bool(spec.get("ring", false)):
		_ring(c, r, tilt, false)
	for m in _moons:  # (each moon goes slowly round: half of the time it is in front)
		var a: float = float(m["ang"]) + _clock * 0.02 / float(m["dist"])
		var mr: float = r * float(m["size"])
		var mc := c + Vector2(cos(a), sin(a) * 0.35).rotated(tilt) * r * float(m["dist"])
		draw_texture_rect(m["tex"], Rect2(mc - Vector2(mr, mr), Vector2(mr, mr) * 2.0), false)


## The rocks of an asteroid field: each tumbles slowly and drifts against the camera at its own PARALLAX.
func _draw_rocks(c: Vector2, r: float) -> void:
	var vp := get_viewport_rect().size
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	var cam_pos := cam.get_screen_center_position() if cam != null else Vector2.ZERO
	var zoom := cam.zoom.x if cam != null else 1.0
	var dir: Vector2 = spec.get("dir", Vector2.UP)
	var along := Vector2(absf(dir.y), absf(dir.x))
	for rock in _rocks:
		var base: Vector2 = vp / 2.0 + (spec.get("at", Vector2.ZERO) * CELL - cam_pos) * zoom * PARALLAX * float(rock["par"]) + dir * (r * 0.9 + 80.0)
		var p: Vector2 = base + (along * float(rock["off"].x) + dir * float(rock["off"].y)) * r
		var ang: float = _clock * float(rock["spin"])
		var pts := PackedVector2Array()
		var shade := PackedColorArray()
		for v in rock["pts"]:
			var q: Vector2 = v.rotated(ang) * r
			pts.append(p + q)
			var lit := clampf(0.55 - q.normalized().dot(Vector2(-0.62, -0.48)) * 0.45, 0.2, 1.0)
			shade.append(Color(rock["col"]).darkened(1.0 - lit))
		draw_polygon(pts, shade)


## A far station: a ring turning on its hub, its spokes, and a few lit windows. A silhouette against space.
func _draw_station(c: Vector2, r: float) -> void:
	var s := r * 0.55
	var dark := Color(_ring_col.r * 0.5, _ring_col.g * 0.5, _ring_col.b * 0.5, 0.95)
	var rot := _clock * 0.05
	draw_arc(c, s, 0.0, TAU, 64, dark, s * 0.07, true)
	draw_arc(c, s * 0.92, 0.0, TAU, 64, Color(dark, 0.55), s * 0.02, true)
	draw_circle(c, s * 0.16, dark)
	for k in 4:
		var a := rot + PI * 0.5 * float(k)
		draw_line(c, c + Vector2(cos(a), sin(a)) * s, dark, s * 0.025, true)
	var rr := RandomNumberGenerator.new()
	rr.seed = int(spec.get("seed", 1))
	for k in 28:
		var a := rot + TAU * float(k) / 28.0
		if rr.randf() < 0.6:
			draw_circle(c + Vector2(cos(a), sin(a)) * s, s * 0.012, Color(_glow, 0.9))
	draw_rect(Rect2(c + Vector2(-s * 0.05, -s * 1.28), Vector2(s * 0.1, s * 0.5)), dark)  # (a docking mast)


## Half of a ring round the body: the back half (behind it) or the front.
func _ring(c: Vector2, r: float, tilt: float, back: bool) -> void:
	for band in 5:
		var rr := r * (1.45 + 0.09 * float(band))
		var pts := PackedVector2Array()
		for i in 49:
			var a := (PI if back else 0.0) + PI * float(i) / 48.0
			pts.append(c + Vector2(cos(a) * rr, sin(a) * rr * 0.22).rotated(tilt))
		draw_polyline(pts, Color(_ring_col, _ring_col.a * (0.6 + 0.4 * float(band % 2))), r * 0.035, true)


## A nebula as an image: soft clouds of the palette's three colours that thin out to the edge.
static func paint_nebula(pal: Array, p_seed: int) -> Image:
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	var n1 := FastNoiseLite.new()
	n1.seed = p_seed
	n1.frequency = 1.7
	n1.fractal_octaves = 4
	var n2 := FastNoiseLite.new()
	n2.seed = p_seed + 7
	n2.frequency = 2.3
	n2.fractal_octaves = 3
	var h := TEX / 2.0
	for y in TEX:
		for x in TEX:
			var nx := (x + 0.5 - h) / h
			var ny := (y + 0.5 - h) / h
			var fall := clampf(1.0 - sqrt(nx * nx + ny * ny), 0.0, 1.0)
			var v := n1.get_noise_2d(nx * 1.4, ny * 1.4) * 0.5 + 0.5
			var w := n2.get_noise_2d(nx * 2.0, ny * 2.0) * 0.5 + 0.5
			var col: Color = pal[0].lerp(pal[1], w).lerp(pal[2], clampf((v - 0.55) * 3.0, 0.0, 1.0))
			col.a = clampf(smoothstep(0.35, 0.8, v) * pow(fall, 1.3) * 0.75, 0.0, 0.8)
			img.set_pixel(x, y, col)
	return img


## The body as an image: `kind` planet (noise land and seas, ice) or gas_giant (bands that swirl), lit from the upper left, `pal` its three colours.
static func paint(kind: String, pal: Array, p_seed: int, tilt: float) -> Image:
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = p_seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 1.6 if kind == "planet" else 1.4
	noise.fractal_octaves = 3
	var cloud := FastNoiseLite.new()
	cloud.seed = p_seed + 1
	cloud.frequency = 2.6
	cloud.fractal_octaves = 2
	var light := Vector3(-0.62, -0.48, 0.62).normalized()
	var h := TEX / 2.0
	for y in TEX:
		for x in TEX:
			var nx := (x + 0.5 - h) / h
			var ny := (y + 0.5 - h) / h
			var d2 := nx * nx + ny * ny
			if d2 > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var nz := sqrt(1.0 - d2)
			var sx := nx / (nz + 0.7)
			var sy := ny / (nz + 0.7)
			var col: Color
			if kind == "planet":
				var v := noise.get_noise_2d(sx, sy)
				col = pal[0].lerp(pal[1], smoothstep(-0.06, 0.12, v))
				col = col.lerp(pal[2], smoothstep(0.78, 0.9, absf(ny)) * 0.8)  # (ice at the poles)
				col = col.lerp(Color(0.95, 0.97, 1.0), smoothstep(0.15, 0.45, cloud.get_noise_2d(sx * 1.3, sy * 2.2)) * 0.75)  # (clouds)
			else:
				var lat := ny * cos(tilt) + nx * sin(tilt)
				var band := sin(lat * 11.0 + noise.get_noise_2d(sx * 0.6, sy * 2.5) * 3.0)
				col = pal[0].lerp(pal[1], 0.5 + 0.5 * band).lerp(pal[2], clampf(noise.get_noise_2d(sx * 3.0, sy * 3.0) * 1.5, 0.0, 0.6))
			var lit := clampf(Vector3(nx, ny, nz).dot(light), 0.0, 1.0)
			var shade := 0.06 + 0.94 * pow(lit, 0.8)
			col = Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
			var edge := clampf((1.0 - sqrt(d2)) * h / 2.0, 0.0, 1.0)  # (a soft edge, two px)
			col.a = edge
			img.set_pixel(x, y, col)
	return img
