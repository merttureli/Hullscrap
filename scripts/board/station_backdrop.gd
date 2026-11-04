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
	_tex = ImageTexture.create_from_image(paint(str(spec["kind"]), pal.map(func(c): return Color(str(c))), int(spec["seed"]), float(spec.get("tilt", 0.0))))
	queue_redraw()


func _process(_dt: float) -> void:
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
	if _tex == null:
		return
	var r := float(spec.get("radius", 360.0))
	var c := centre()
	var tilt := float(spec.get("tilt", 0.0))
	if bool(spec.get("ring", false)):
		_ring(c, r, tilt, true)
	for k in 6:  # the rim of air, a few soft rings
		draw_circle(c, r * (1.0 + 0.012 * float(k + 1)), Color(_glow, 0.05))
	draw_texture_rect(_tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
	if bool(spec.get("ring", false)):
		_ring(c, r, tilt, false)


## Half of a ring round the body: the back half (behind it) or the front.
func _ring(c: Vector2, r: float, tilt: float, back: bool) -> void:
	for band in 5:
		var rr := r * (1.45 + 0.09 * float(band))
		var pts := PackedVector2Array()
		for i in 49:
			var a := (PI if back else 0.0) + PI * float(i) / 48.0
			pts.append(c + Vector2(cos(a) * rr, sin(a) * rr * 0.22).rotated(tilt))
		draw_polyline(pts, Color(_ring_col, _ring_col.a * (0.6 + 0.4 * float(band % 2))), r * 0.035, true)


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
