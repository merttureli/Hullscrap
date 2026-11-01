extends Control
## The Hollow tide's fog in sector space (docs/waves/playtest_2.md S4): as the tide nears the ship's place (sector.gd `pressure`, 0 to 1,
## set by sector_view.gd each frame) a dark-violet fog creeps in from the left of the screen, the side the tide comes from (it moves along
## the map's +x, which is world -x here). Its width and its opacity grow with the pressure; at 1 it covers about a third of the screen
## and veils the other three edges. Cheap: two gradient quads, nine slowly drifting soft blotches and the edge veils; no input.

const FOG := Color(0.32, 0.17, 0.48)  ## a dark, murky violet: it has to read against black space
const WIDTH_AT_1 := 0.34  ## the band's share of the screen's width at pressure 1
const ALPHA_AT_1 := 0.85  ## its opacity at the screen's left edge at pressure 1
const VEIL_AT_1 := 0.10  ## the share of the screen the veil on the other three edges reaches at pressure 1
const BLOTCHES := 9

var pressure := 0.0  ## 0 to 1: nothing is drawn at 0
var _t := 0.0
var _blob: GradientTexture2D  # a soft round blotch, made when first drawn


## The band's width in px on a screen `screen_w` px wide.
static func band_width(p: float, screen_w: float) -> float:
	return screen_w * WIDTH_AT_1 * clampf(p, 0.0, 1.0)


## The band's opacity at the screen's edge.
static func band_alpha(p: float) -> float:
	return ALPHA_AT_1 * clampf(p, 0.0, 1.0)


## A round blotch that fades out to nothing at its edge.
static func _make_blob() -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([FOG.lightened(0.22), Color(FOG.lightened(0.22), 0.0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128
	t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


## A steady 0 to 1 per blotch `i` (no randomness: the fog is the same every time).
static func _unit(i: int, salt: float) -> float:
	return fposmod(sin(float(i) * 12.9898 + salt * 78.233) * 43758.5453, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(dt: float) -> void:
	_t += dt
	visible = pressure > 0.0
	if visible:
		queue_redraw()


func _draw() -> void:
	if pressure <= 0.0:
		return
	if _blob == null:
		_blob = _make_blob()
	var w := size.x
	var h := size.y
	var band := band_width(pressure, w)
	var a := band_alpha(pressure) * (1.0 + 0.06 * sin(_t * 0.7))
	var clear := Color(FOG, 0.0)
	draw_polygon(PackedVector2Array([Vector2(0.0, 0.0), Vector2(band, 0.0), Vector2(band, h), Vector2(0.0, h)]), PackedColorArray([Color(FOG, a), clear, clear, Color(FOG, a)]))
	var inner := band * 0.5  # denser close to the edge
	var core := Color(FOG, a * 0.5)
	var core_clear := Color(core, 0.0)
	draw_polygon(PackedVector2Array([Vector2(0.0, 0.0), Vector2(inner, 0.0), Vector2(inner, h), Vector2(0.0, h)]), PackedColorArray([core, core_clear, core_clear, core]))
	for i in BLOTCHES:  # soft blobs drifting through the band, so it is not a flat wash
		var y := (float(i) + 0.5) / float(BLOTCHES) * h + sin(_t * 0.13 + float(i) * 1.7) * h / float(BLOTCHES)
		var x := band * (0.2 + 0.7 * _unit(i, 1.0)) + sin(_t * 0.09 + float(i) * 2.3) * band * 0.2
		var r := (0.5 + 0.5 * _unit(i, 2.0)) * (band * 0.28 + 30.0)
		draw_texture_rect(_blob, Rect2(Vector2(x - r, y - r), Vector2(r, r) * 2.0), false, Color(1.0, 1.0, 1.0, 0.55 * pressure))
	var v := VEIL_AT_1 * pressure
	var va := 0.45 * pressure * pressure
	var edge := Color(FOG, va)
	var edge_clear := Color(FOG, 0.0)
	var tv := h * v
	var rv := w * v
	draw_polygon(PackedVector2Array([Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w, tv), Vector2(0.0, tv)]), PackedColorArray([edge, edge, edge_clear, edge_clear]))
	draw_polygon(PackedVector2Array([Vector2(0.0, h), Vector2(w, h), Vector2(w, h - tv), Vector2(0.0, h - tv)]), PackedColorArray([edge, edge, edge_clear, edge_clear]))
	draw_polygon(PackedVector2Array([Vector2(w, 0.0), Vector2(w, h), Vector2(w - rv, h), Vector2(w - rv, 0.0)]), PackedColorArray([edge, edge, edge_clear, edge_clear]))
