extends RefCounted
## The swappable art registry: every component is drawn through draw_component(), by id. If
## res://art/components/<id>.png (or .svg) exists, that texture is drawn, rotated; otherwise a
## flat placeholder (see art/README.md for how to drop art in). On top of either it overlays the
## component's state: a heat bar, an orange "!" when overheated, a yellow gear when malfunctioning,
## grey when disabled and a row of hp pips when damaged. Drawing only, no game logic.

const Stats = preload("res://scripts/sim/stats.gd")
const ART_DIR := "res://art/components"
const EXTENSIONS: Array[String] = ["png", "svg"]
const HEAT_SHOWN := 0.3  ## the heat bar appears above this fraction of the limit
const GREY := Color("#5b5f6b")
const HEAT_COLD := Color("#f2c14e")
const HEAT_HOT := Color("#ff3b2f")
const OVERHEAT_COLOR := Color("#ff8a1f")
const MALFUNCTION_COLOR := Color("#ffe14a")
const HP_COLOR := Color("#5bd67a")
const HP_LOST_COLOR := Color("#7a2530")
## Placeholder accent per line: scrap gets a hazard-stripe corner, neon a bright outline.
const SCRAP_ACCENT := Color("#f2c14e")
const NEON_ACCENT := Color("#3ef0ff")

## Where the art lives; tests point it elsewhere.
static var art_dir := ART_DIR
static var _cache := {}  # "<dir>/<id>" -> Texture2D, or null when there is no art


## The art texture of component `id`, or null when there is none (the placeholder is drawn).
## Looks for <art_dir>/<id>.png, then .svg. The answer is cached; clear_cache() forgets it.
static func texture_for(id: String) -> Texture2D:
	var key := art_dir + "/" + id
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	for ext in EXTENSIONS:
		var path := "%s/%s.%s" % [art_dir, id, ext]
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		elif FileAccess.file_exists(path):  # dropped in but not imported yet: read the file itself
			var img := Image.load_from_file(path)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
		if tex != null:
			break
	_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()


## What the state overlay shows for a component: {status, heat (0..1), show_heat, hp, max_hp,
## show_hp}. `inst` may be empty (a ghost): everything is then healthy and cold.
static func marks(def: Dictionary, inst: Dictionary) -> Dictionary:
	var max_hp := Stats.max_hp(def)
	var limit := maxf(1.0, float(def.get("heat_limit", Stats.DEFAULT_HEAT_LIMIT)))
	var heat := clampf(float(inst.get("heat", 0.0)) / limit, 0.0, 1.0)
	var hp := int(inst.get("hp", max_hp))
	return {
		"status": str(inst.get("status", "ok")),
		"heat": heat, "show_heat": heat > HEAT_SHOWN,
		"hp": hp, "max_hp": max_hp, "show_hp": hp < max_hp,
	}


## A 1-2 letter name for a system: "R1" for Reactor Mk1, the initials of two words ("OG"), else two letters.
static func label_of(def: Dictionary) -> String:
	var words: PackedStringArray = str(def.get("name", def.get("id", "?"))).split(" ", false)
	if words.is_empty():
		return "?"
	if words.size() > 1 and words[-1].begins_with("Mk"):
		return words[0][0] + words[-1].substr(2)
	return words[0][0] + words[1][0] if words.size() > 1 else words[0].substr(0, 2)


## Draw component `def` into `rect` (the screen rectangle of its whole, already rotated, footprint)
## on `canvas` (a CanvasItem; call this from its _draw). `inst`: the runtime state {rot, hp, heat,
## status}. `cell_px`: pixels per grid cell. `opts`: powered (default true; false marks a consumer
## without power), alpha (default 1, for ghosts).
static func draw_component(canvas, rect: Rect2, def: Dictionary, inst: Dictionary, cell_px: float, opts := {}) -> void:
	var m := marks(def, inst)
	var alpha := float(opts.get("alpha", 1.0))
	var tex := texture_for(str(def.get("id", "")))
	if tex != null:
		_draw_art(canvas, tex, rect, def, int(inst.get("rot", 0)), cell_px, m["status"], alpha)
	else:
		_draw_placeholder(canvas, rect.grow(-2), def, cell_px, m, bool(opts.get("powered", true)), alpha)
	_draw_marks(canvas, rect.grow(-2), m, alpha)


## The art texture, turned `rot` quarter turns clockwise about the centre of the footprint. The
## texture is authored at the unrotated footprint size, facing up.
static func _draw_art(canvas, tex: Texture2D, rect: Rect2, def: Dictionary, rot: int, cell_px: float, status: String, alpha: float) -> void:
	var size := Vector2(float(def["size"][0]), float(def["size"][1])) * cell_px
	var tint := Color(1, 1, 1, alpha)
	if status == "disabled":
		tint = Color(0.45, 0.45, 0.5, alpha)
	canvas.draw_set_transform(rect.get_center(), posmod(rot, 4) * PI / 2.0, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-size / 2.0, size), false, tint)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_placeholder(canvas, r: Rect2, def: Dictionary, cell_px: float, m: Dictionary, powered: bool, alpha: float) -> void:
	var col := Color(def.get("color", "#ff00ff"))
	var line := str(def.get("line", Stats.DEFAULT_LINE))
	var status: String = m["status"]
	var out_of_action := status != "ok"
	var unpowered := not powered and int(def.get("power", 0)) < 0 and not out_of_action
	var fill := col.darkened(0.4) if line == "neon" else col  # neon: a dark panel with a glowing edge
	if status == "disabled":
		fill = GREY
	elif status == "overheated":
		fill = fill.lerp(OVERHEAT_COLOR, 0.35).darkened(0.25)
	elif status == "malfunction" or unpowered:
		fill = fill.darkened(0.55)
	var label_col := Color(0, 0, 0, 0.5 if (unpowered or out_of_action) else 0.85)
	canvas.draw_rect(r, _a(fill, alpha))
	match line:
		"scrap":
			canvas.draw_rect(r, _a(col.darkened(0.4), alpha), false, 1.5)
			_draw_hazard_corner(canvas, r, cell_px * 0.75, alpha)
		"neon":
			canvas.draw_rect(r.grow(1.0), _a(Color(NEON_ACCENT, 0.3), alpha), false, 5.0)  # glow
			canvas.draw_rect(r, _a(NEON_ACCENT, alpha), false, 2.5)
		_:
			canvas.draw_rect(r, _a(col.darkened(0.4), alpha), false, 1.5)
	_draw_text(canvas, label_of(def), r.get_center(), 14, _a(label_col, alpha), true)
	if unpowered:
		_draw_no_power(canvas, r.position + Vector2(r.size.x - 8, 9))


## A right-triangle of yellow and black diagonal stripes in the bottom-left corner of `r`.
static func _draw_hazard_corner(canvas, r: Rect2, s: float, alpha: float) -> void:
	var x0 := r.position.x
	var y1 := r.end.y
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(x0, y1 - s), Vector2(x0, y1), Vector2(x0 + s, y1)]), _a(SCRAP_ACCENT, alpha))
	for k in [1.0 / 3.0, 2.0 / 3.0]:
		canvas.draw_line(Vector2(x0, y1 - s + s * k), Vector2(x0 + s - s * k, y1), _a(Color.BLACK, alpha), 3.0)


## The state overlay: heat bar along the bottom, hp pips at the top left, a mark at the top right.
static func _draw_marks(canvas, r: Rect2, m: Dictionary, alpha: float) -> void:
	if m["show_heat"]:
		var bar := Rect2(r.position.x + 4, r.end.y - 8, r.size.x - 8, 4)
		canvas.draw_rect(bar, _a(Color(0, 0, 0, 0.6), alpha))
		var t: float = m["heat"]
		var hot := HEAT_COLD.lerp(HEAT_HOT, clampf((t - HEAT_SHOWN) / (1.0 - HEAT_SHOWN), 0.0, 1.0))
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), _a(hot, alpha))
	if m["show_hp"]:
		var n: int = m["max_hp"]
		var pip := minf(5.0, (r.size.x - 8.0) / maxf(1.0, float(n)))
		for i in n:
			var p := Rect2(r.position + Vector2(4.0 + i * pip, 4.0), Vector2(pip - 1.0, 4.0))
			canvas.draw_rect(p, _a(HP_COLOR if i < int(m["hp"]) else HP_LOST_COLOR, alpha))
	var at := Vector2(r.end.x - 12, r.position.y + 13)
	match m["status"]:
		"overheated":
			canvas.draw_circle(at, 10.0, _a(Color(0, 0, 0, 0.7), alpha))
			_draw_text(canvas, "!", at, 20, _a(OVERHEAT_COLOR, alpha), true)
		"malfunction":
			canvas.draw_circle(at, 10.0, _a(Color(0, 0, 0, 0.7), alpha))
			_draw_text(canvas, "⚙" if ThemeDB.fallback_font.has_char(0x2699) else "M", at, 16, _a(MALFUNCTION_COLOR, alpha), true)


## The "no power" mark: a red lightning bolt, or a red dot when the font has no such glyph.
static func _draw_no_power(canvas, at: Vector2) -> void:
	if ThemeDB.fallback_font.has_char(0x26A1):
		canvas.draw_string(ThemeDB.fallback_font, at + Vector2(-6, 5), "⚡", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.RED)
	else:
		canvas.draw_circle(at, 3.5, Color.RED)


## Text centred on `centre`, with a dark outline when `outlined`.
static func _draw_text(canvas, text: String, centre: Vector2, size: int, col: Color, outlined := false) -> void:
	var font := ThemeDB.fallback_font
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var at := centre - Vector2(extent.x / 2.0, extent.y / 2.0 - font.get_ascent(size))
	if outlined and col.get_luminance() > 0.5:
		canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, col.a * 0.9))
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func _a(col: Color, alpha: float) -> Color:
	return Color(col, col.a * alpha)
