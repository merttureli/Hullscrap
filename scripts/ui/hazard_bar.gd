extends Control
## The fight's hazard line (hazards.gd): a slim panel under the hint at the top of the screen with the hazard's text
## ("ION STORM: shields recharge at half speed"), its colour, and for the star and the current an arrow toward them
## (the camera does not turn, so the world direction is the screen direction). In the last seconds before a flare or a
## surge it reads "Flare in 3" and pulses. Hidden when the fight has no hazard. bind() it to the fight's arena (null:
## none); also draws the map's small hazard badge (badge). Drawing only.

const Hazards = preload("res://scripts/combat/hazards.gd")

const HEIGHT := 30.0
const TOP := 62.0  ## px from the top: under the two hint lines
const BG := Color(0.04, 0.07, 0.11, 0.82)
const TEXT := Color("#f2f6fb")

var arena = null


func _init() -> void:
	size = Vector2(300.0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func bind(p_arena) -> void:
	arena = p_arena
	visible = false


func _process(_dt: float) -> void:
	visible = arena != null and not arena.hazard.is_empty()
	if visible:
		var text := Hazards.hud_line(arena)
		var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 64.0
		size = Vector2(w, HEIGHT)
		position = Vector2((get_viewport_rect().size.x - w) / 2.0, TOP)
		queue_redraw()


func _draw() -> void:
	if arena == null or arena.hazard.is_empty():
		return
	var h: Dictionary = arena.hazard
	var d := Hazards.def(str(h["id"]))
	var col := Color(str(d.get("color", "#ffffff")))
	var warn: bool = d.has("warn_s") and Hazards.next_in(arena) <= float(d["warn_s"]) + 1e-6
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0) if warn else 0.0
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_rect(Rect2(Vector2.ZERO, size), col.lerp(Color.WHITE, pulse * 0.6), false, 2.0)
	var x := 32.0
	if Hazards.has_dir(h):
		_arrow(Vector2(22.0, HEIGHT / 2.0), Hazards.dir_vec(h), col)
		x = 40.0
	else:
		draw_circle(Vector2(18.0, HEIGHT / 2.0), 5.0, col)
	draw_string(ThemeDB.fallback_font, Vector2(x, 20.0), Hazards.hud_line(arena), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, TEXT.lerp(col, pulse))


## An arrow of colour `col` at `at` pointing along the unit vector `dir`.
func _arrow(at: Vector2, dir: Vector2, col: Color) -> void:
	var side := dir.rotated(PI / 2.0)
	draw_line(at - dir * 8.0, at + dir * 8.0, col, 2.5, true)
	draw_colored_polygon(PackedVector2Array([at + dir * 11.0, at + dir * 3.0 + side * 5.0, at + dir * 3.0 - side * 5.0]), col)


## The small round badge a map node wears when it has hazard `h` ({id, dir}): the hazard's colour with its letter. Drawn on
## `canvas` (the map view), centred at `at`.
static func badge(canvas: CanvasItem, at: Vector2, h: Dictionary) -> void:
	var d := Hazards.def(str(h.get("id", "")))
	if d.is_empty():
		return
	canvas.draw_circle(at, 8.5, Color("#10151c"))
	canvas.draw_circle(at, 7.0, Color(str(d["color"])))
	canvas.draw_string(ThemeDB.fallback_font, at + Vector2(-4.0, 5.0), str(d["glyph"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#10151c"))
