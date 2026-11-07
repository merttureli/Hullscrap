extends Node2D
## Screen-space starfield behind everything: the ship stays centred and space moves (Raft-style). With the space art
## (art/space: stars_far, stars_mid, stars_near tiling layers and a nebula per region, art/README.md) the layers are
## drawn repeated and shifted by the camera's place times their `parallax`, and the nebula of `region` (set by the
## sector view; "" draws none) is tinted by its `suggested_tints`. Without the art, code-drawn dots. `drift` (px/s for
## the nearest stars) moves the sky on its own: debris_view.gd points it along the current on the build screen.

const Art = preload("res://scripts/view/art.gd")
const LAYERS: Array[String] = ["stars_far", "stars_mid", "stars_near"]
const NEBULA_SCALE := 3.0  ## the nebula overlay is drawn this many times its size
const NEBULA_GAP := 1.15  ## and repeated at this many times its drawn size
const SPACE := Color("#05070c")

@export var drift := Vector2(-22, 7)  # pixels per second for the nearest stars
@export var count := 260

var stars: Array = []  # [unit position, depth 0.2..1, radius]
var region := ""  ## the nebula drawn: clans, concord, lumen, boneyard, gate, or "" for none
var cam_pos := Vector2.ZERO  ## the camera's place in the world; the layers move against it
var _offset := Vector2.ZERO  # the drift integrated over time, so a drift that changes (debris_view.gd follows the current) never makes the sky jump
var _layers: Array = []  # [texture, parallax] of the art layers found
var _nebulae := {}  # region -> [texture, tint, parallax], or null when there is no art


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # visual only; fixed so the sky looks the same every run
	for i in count:
		stars.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.2, 1.0), rng.randf_range(0.6, 1.8)])
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for name in LAYERS:
		var s = Art.load_sheet("%s/space/%s" % [Art.root, name])
		if s != null:
			_layers.append([s.texture, float(s.meta.get("parallax", 0.1))])


func _process(delta: float) -> void:
	_offset += drift * delta
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	if cam != null:
		cam_pos = cam.get_screen_center_position()
	queue_redraw()


## The nebula art of `id` ([texture, tint, parallax]), or null.
func _nebula(id: String):
	if not _nebulae.has(id):
		var art_id: String = "nebula_clan" if id == "clans" else "nebula_" + id
		var s = Art.load_sheet("%s/space/%s" % [Art.root, art_id])
		_nebulae[id] = null
		if s != null:
			var tint := Color(str(s.meta.get("suggested_tints", {}).get("region", "#ffffff")))
			_nebulae[id] = [s.texture, tint, float(s.meta.get("parallax", 0.06))]
	return _nebulae[id]


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), SPACE)
	var neb = _nebula(region) if region != "" else null
	if neb != null:
		var tex: Texture2D = neb[0]
		var size := Vector2(tex.get_size()) * NEBULA_SCALE
		var step := size * NEBULA_GAP
		var shift := -(cam_pos * float(neb[2]) - _offset * 0.2)
		var start := Vector2(fposmod(shift.x, step.x), fposmod(shift.y, step.y)) - step
		var y := start.y
		while y < vp.y:
			var x := start.x
			while x < vp.x:
				draw_texture_rect(tex, Rect2(Vector2(x, y), size), false, neb[1])
				x += step.x
			y += step.y
	if _layers.is_empty():
		for s in stars:
			var depth: float = s[1]
			var p: Vector2 = s[0] * vp + _offset * depth
			p = Vector2(fposmod(p.x, vp.x), fposmod(p.y, vp.y))
			draw_circle(p, s[2] * depth, Color(1, 1, 1, 0.3 + 0.6 * depth))
		return
	for l in _layers:
		var tex: Texture2D = l[0]
		var k: float = l[1]
		var size := Vector2(tex.get_size())
		var shift := -cam_pos * k + _offset * (k / 0.35)
		var start := Vector2(fposmod(shift.x, size.x), fposmod(shift.y, size.y)) - size
		draw_texture_rect(tex, Rect2(start, vp + size * 2.0), true)
