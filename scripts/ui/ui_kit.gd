extends RefCounted
## The game's UI skin (docs/ART_STYLE.md "UI"): panels, bars, insets, cards, tabs, buttons, tooltips and icons, drawn
## on any CanvasItem from its _draw. Each piece first looks for the pixel UI kit in art/ui/ (art/_src/ui_kit.py: a
## sheet per piece whose frames are its states, e.g. button normal/hover/pressed, card scrap/steel/neon/gold, with
## the 9-slice margins in its JSON's "nine_slice"; the icons are named frames of icons_res, icons_mode and icons_cat)
## and draws a flat code version in the same palette when it is not there. The kit is drawn at PX screen px per
## source px. Static, drawing only.

const Art = preload("res://scripts/view/art.gd")

const PANEL_BG := Color("#1f2630")
const ROW_BG := Color("#2a3340")
const INSET_BG := Color("#151a22")
const EDGE := Color("#cfd6df")
const EDGE_DIM := Color("#59667a")
const HIGHLIGHT := Color(1, 1, 1, 0.1)
const SHADE := Color(0, 0, 0, 0.35)
const TEXT := Color("#eef2f7")
const DIM_TEXT := Color("#97a3b3")
const GOOD := Color("#6bd34a")
const BAD := Color("#e0413b")
const AMBER := Color("#e1a136")
const SHIELD := Color("#4fa3ff")
const O2_LOW := Color("#e88aa0")
## Card borders by line (docs/ART_STYLE.md lines): scrap rust, standard steel, neon cyan, unique gold.
const LINE_COLORS := {"scrap": Color("#9c5a33"), "standard": Color("#8d9aab"), "neon": Color("#3cf2ff"), "unique": Color("#f2c14e")}
const CARD_FRAMES := {"scrap": "scrap", "standard": "steel", "neon": "neon", "unique": "gold"}  ## line -> frame of the kit's card sheet
const PX := 2.0  ## screen px per source px of the kit
const ICON_SHEETS: Array[String] = ["icons_res", "icons_mode", "icons_cat"]
const MATERIAL_COLORS := {"scrap": Color("#9aa0a6"), "copper": Color("#d98a4e"), "polymer": Color("#e8e1c8"), "titanium": Color("#b9c6d6"),
	"silicon": Color("#6c7a89"), "crystal": Color("#7fdbff"), "plasma_cell": Color("#ff7ae0"), "nanite_paste": Color("#7dff9b"),
	"credits": Color("#e1a136"), "fuel": Color("#ff8a1e"), "missile": Color("#c9ced6"),
	"steel": Color("#7c8aa5"), "alloy": Color("#a9c4a0"), "conductor": Color("#e8c15a"), "glass_lattice": Color("#9fe8e0")}

static var _nine := {}  # "sheet:frame" -> StyleBoxTexture, or null when the kit has no such frame
static var _icons := {}  # id -> [texture, region] or null
static var _sheets := {}  # kit sheet name -> SpriteSheet or null
static var _cursors := {}  # cursor name -> [ImageTexture, hotspot] or null
static var _bold: Font
static var _italic: Font


## Is `e` a mouse wheel step (either axis)? A panel under the pointer marks these handled (accept_event), so the world behind it never zooms.
static func is_wheel(e: InputEvent) -> bool:
	return e is InputEventMouseButton and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]


# --- fonts and text ----------------------------------------------------------------------------------------------

static func font() -> Font:
	return ThemeDB.fallback_font


## The fallback font, emboldened, for titles.
static func bold() -> Font:
	if _bold == null:
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.variation_embolden = 0.7
		_bold = f
	return _bold


## The fallback font, slanted, for lore lines.
static func italic() -> Font:
	if _italic == null:
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.22, 1.0), Vector2.ZERO)
		_italic = f
	return _italic


static func text_width(s: String, size: int, f: Font = null) -> float:
	return (f if f != null else font()).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Text with its baseline at `at` and a 1 px shadow; `width` > 0 aligns it in that width and clips it there.
static func text(cv: CanvasItem, s: String, at: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, f: Font = null) -> void:
	var ff: Font = f if f != null else font()
	var t := fit(s, width, size, ff) if width > 0.0 else s
	cv.draw_string(ff, at + Vector2(1, 1), t, align, width, size, Color(0, 0, 0, 0.6 * col.a))
	cv.draw_string(ff, at, t, align, width, size, col)


## `s` cut to fit `width` px with an ellipsis.
static func fit(s: String, width: float, size: int, f: Font = null) -> String:
	if width <= 0.0 or text_width(s, size, f) <= width:
		return s
	var t := s
	while t.length() > 1 and text_width(t + "...", size, f) > width:
		t = t.substr(0, t.length() - 1)
	return t.strip_edges() + "..."


## `s` broken into lines no wider than `width` px (greedy, by words, or by the chunks between `sep`s; a chunk too
## long for a line is cut).
static func wrap(s: String, width: float, size: int, f: Font = null, sep := " ") -> PackedStringArray:
	var out := PackedStringArray()
	for para in s.split("\n"):
		var line := ""
		for w in para.split(sep, false):
			w = w.strip_edges()
			var next := w if line == "" else line + sep + w
			if line != "" and text_width(next, size, f) > width:
				out.append(line)
				line = w
			else:
				line = next
		out.append(fit(line, width, size, f))
	return out


# --- frames -------------------------------------------------------------------------------------------------------

## The kit's sheet `name` (art/ui/<name>.png + .json), or null.
static func kit(name: String) -> RefCounted:
	if not _sheets.has(name):
		_sheets[name] = Art.load_sheet("%s/ui/%s" % [Art.root, name])
	return _sheets[name]


## Forget the kit (tests point Art.root elsewhere).
static func clear_cache() -> void:
	_nine.clear()
	_icons.clear()
	_sheets.clear()
	_cursors.clear()


## The 9-slice of frame `frame` of the kit's sheet `name`, or null when it has not landed.
static func nine_slice(name: String, frame := "normal") -> StyleBoxTexture:
	var key := name + ":" + frame
	if _nine.has(key):
		return _nine[key]
	var sb: StyleBoxTexture = null
	var s = kit(name)
	var ns = s.meta.get("nine_slice") if s != null else null
	if ns is Dictionary and s.has_anim(frame):
		var m = ns.get("margins", {})
		var mm: Array = [m.get("left", 4), m.get("top", 4), m.get("right", 4), m.get("bottom", 4)] if m is Dictionary else [4, 4, 4, 4]
		sb = StyleBoxTexture.new()
		sb.texture = s.texture
		sb.region_rect = s.region(s.start_of(frame))
		sb.texture_margin_left = float(mm[0])
		sb.texture_margin_top = float(mm[1])
		sb.texture_margin_right = float(mm[2])
		sb.texture_margin_bottom = float(mm[3])
	_nine[key] = sb
	return sb


## Draw frame `frame` of the kit's 9-slice `name` over `r` (true), or nothing when it is not there (false).
static func nine(cv: CanvasItem, name: String, r: Rect2, frame := "normal", mod := Color.WHITE) -> bool:
	var sb := nine_slice(name, frame)
	if sb == null:
		return false
	sb.modulate_color = mod
	cv.draw_set_transform(r.position, 0.0, Vector2(PX, PX))
	cv.draw_style_box(sb, Rect2(Vector2.ZERO, r.size / PX))
	cv.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true


## A chunky window (the palette, the card): slate fill, 2 px light border, a 1 px inner highlight, rivets in the corners.
static func panel(cv: CanvasItem, r: Rect2, alpha := 0.95) -> void:
	if nine(cv, "panel", r, "normal", Color(1, 1, 1, alpha)):
		return
	cv.draw_rect(r, Color(PANEL_BG, alpha))
	cv.draw_rect(r.grow(-1), EDGE, false, 2.0)
	cv.draw_line(r.position + Vector2(3, 3), Vector2(r.end.x - 3, r.position.y + 3), HIGHLIGHT, 1.0)
	cv.draw_line(r.position + Vector2(3, 3), Vector2(r.position.x + 3, r.end.y - 3), HIGHLIGHT, 1.0)
	for c in [r.position + Vector2(5, 5), Vector2(r.end.x - 7, r.position.y + 5), Vector2(r.position.x + 5, r.end.y - 7), r.end - Vector2(7, 7)]:
		cv.draw_rect(Rect2(c, Vector2(2, 2)), EDGE_DIM)


## The thin HUD frame (the top bar, the mode bar, the log, the hints).
static func bar(cv: CanvasItem, r: Rect2, alpha := 0.95) -> void:
	if nine(cv, "bar", r, "normal", Color(1, 1, 1, alpha)):
		return
	cv.draw_rect(r, Color(PANEL_BG, alpha))
	cv.draw_rect(r.grow(-1), EDGE_DIM.lightened(0.25), false, 2.0)
	cv.draw_line(r.position + Vector2(3, 3), Vector2(r.end.x - 3, r.position.y + 3), HIGHLIGHT, 1.0)


## A header strip with `title` on it.
static func title_bar(cv: CanvasItem, r: Rect2, title: String, size := 14) -> void:
	var x := 10.0
	if nine(cv, "titlebar", r):
		x = 14.0 * PX
	else:
		cv.draw_rect(r, ROW_BG)
		cv.draw_rect(Rect2(r.position, Vector2(4, r.size.y)), AMBER)
	text(cv, title, Vector2(r.position.x + x, r.get_center().y + size * 0.36), size, TEXT, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - x - 6.0, bold())


## A sunken well (a list, a picture).
static func inset(cv: CanvasItem, r: Rect2) -> void:
	if nine(cv, "inset", r):
		return
	cv.draw_rect(r, INSET_BG)
	cv.draw_rect(r, EDGE_DIM, false, 1.0)
	cv.draw_line(r.position, Vector2(r.end.x, r.position.y), SHADE, 1.0)


## A floating note (the cursor note, a tooltip), its rim in `edge` when the kit is not there.
static func tooltip(cv: CanvasItem, r: Rect2, edge: Color) -> void:
	if not nine(cv, "tooltip", r):
		cv.draw_rect(r, Color(PANEL_BG, 0.96))
		cv.draw_rect(r, edge, false, 1.0)


## A palette card: the line's frame, lit when `hover`, framed in amber when `selected`.
static func card(cv: CanvasItem, r: Rect2, line: String, selected: bool, hover: bool) -> void:
	var edge: Color = LINE_COLORS.get(line, LINE_COLORS["standard"])
	if nine(cv, "card", r, CARD_FRAMES.get(line, "steel")):
		var hl := "selected" if selected else ("hover" if hover else "")
		if hl != "":
			nine(cv, "highlight", r.grow(2.0 * PX), hl)
		return
	cv.draw_rect(r, ROW_BG.lightened(0.08) if hover else ROW_BG)
	cv.draw_rect(r.grow(-1), edge, false, 2.0)
	cv.draw_line(r.position + Vector2(2, 2), Vector2(r.end.x - 2, r.position.y + 2), HIGHLIGHT, 1.0)
	if selected:
		cv.draw_rect(r.grow(1), AMBER, false, 2.0)
		cv.draw_rect(r.grow(3), Color(AMBER, 0.3), false, 2.0)


## A category tab: raised and lit when `on`.
static func tab(cv: CanvasItem, r: Rect2, on: bool, hover: bool) -> void:
	if nine(cv, "tab", r, "on" if on else "off", Color(1.2, 1.2, 1.2) if hover and not on else Color.WHITE):
		return
	cv.draw_rect(r, ROW_BG.lightened(0.12) if on else (ROW_BG.lightened(0.05) if hover else INSET_BG))
	cv.draw_rect(r, AMBER if on else EDGE_DIM, false, 2.0 if on else 1.0)
	if on:
		cv.draw_line(Vector2(r.position.x + 2, r.end.y - 2), Vector2(r.end.x - 2, r.end.y - 2), AMBER, 2.0)


## A button: `lit` (the active mode) pressed in, `hover` with its amber rim.
static func button(cv: CanvasItem, r: Rect2, lit: bool, hover: bool) -> void:
	if nine(cv, "button", r, "pressed" if lit else ("hover" if hover else "normal")):
		return
	cv.draw_rect(r, Color("#3a3020") if lit else (ROW_BG.lightened(0.08) if hover else ROW_BG))
	cv.draw_rect(r.grow(-1), AMBER if lit else EDGE_DIM, false, 2.0)
	cv.draw_line(r.position + Vector2(2, 2), Vector2(r.end.x - 2, r.position.y + 2), Color(1, 1, 1, 0.16 if lit else 0.08), 1.0)


## A vertical scroll bar in `r`: the thumb shows `frac` of the content, `at` (0..1) down it.
static func scrollbar(cv: CanvasItem, r: Rect2, frac: float, at: float) -> void:
	var h := maxf(r.size.y * frac, 24.0)
	var thumb := Rect2(r.position.x, r.position.y + (r.size.y - h) * at, r.size.x, h)
	if nine(cv, "scrollbar", r, "track"):
		nine(cv, "scrollbar", thumb, "thumb")
		return
	cv.draw_rect(r, Color(0, 0, 0, 0.35))
	cv.draw_rect(thumb, EDGE_DIM)


## A small tag ("Mk2", "Unique") in colour `col`, `at` its top-left; returns its width.
static func chip(cv: CanvasItem, s: String, at: Vector2, col: Color, size := 11) -> float:
	var w := text_width(s, size, bold()) + 10.0
	var r := Rect2(at, Vector2(w, size + 7))
	cv.draw_rect(r, Color(col, 0.22))
	cv.draw_rect(r, col, false, 1.0)
	cv.draw_string(bold(), at + Vector2(5, size + 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col.lightened(0.25))
	return w


## Keyword chips (describe.gd keyword()) in rows of at most `width` px, from `at`: [[Rect2, keyword], ...].
static func chip_layout(kws: Array, at: Vector2, width: float, size := 11) -> Array:
	var out := []
	var x := 0.0
	var y := 0.0
	for k in kws:
		var w := text_width(k["label"], size, bold()) + 10.0
		if x > 0.0 and x + w > width:
			x = 0.0
			y += size + 11.0
		out.append([Rect2(at + Vector2(x, y), Vector2(w, size + 7)), k])
		x += w + 5.0
	return out


## One keyword chip in rect `r`, in the keyword's colour; `lit` (the mouse is on it) fills it more.
static func keyword_chip(cv: CanvasItem, r: Rect2, k: Dictionary, size := 11, lit := false) -> void:
	var col: Color = k["color"]
	cv.draw_rect(r, Color(col, 0.34 if lit else 0.18))
	cv.draw_rect(r, Color(col, 0.9 if lit else 0.6), false, 1.0)
	cv.draw_string(bold(), r.position + Vector2(5, size + 2), k["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## A note of `lines` (UiKit.wrap them to the width wanted), its top left at `at` (the caller keeps it on screen); returns its rect.
static func note(cv: CanvasItem, lines: PackedStringArray, at: Vector2, edge: Color, size := 12) -> Rect2:
	var w := 16.0
	for l in lines:
		w = maxf(w, text_width(l, size) + 16.0)
	var h: float = lines.size() * (size + 4.0) + 12.0
	var r := Rect2(at, Vector2(w, h))
	tooltip(cv, r, edge)
	for i in lines.size():
		text(cv, lines[i], at + Vector2(8, 8 + size + i * (size + 4.0)), size, TEXT)
	return r


## The kit's mouse cursor `name` (pointer, place, remove, invalid; the 32 px set) as [texture, hotspot], or null.
static func cursor(name: String) -> Variant:
	if _cursors.has(name):
		return _cursors[name]
	var found = null
	var s = kit("cursors_x2")
	if s != null and s.has_anim(name):
		var img: Image = s.image.get_region(Rect2i(s.region(s.start_of(name))))
		var hot = s.anchors.get(name, Vector2.ZERO)
		found = [ImageTexture.create_from_image(img), Vector2(hot)]
	_cursors[name] = found
	return found


# --- icons ----------------------------------------------------------------------------------------------------------

## The kit's icon `id` as [texture, source region], or null.
static func icon_art(id: String) -> Variant:
	if _icons.has(id):
		return _icons[id]
	var found = null
	for sheet_name in ICON_SHEETS:
		var s = kit(sheet_name)
		if s != null and s.has_anim(id):
			found = [s.texture, s.region(s.start_of(id))]
			break
	_icons[id] = found
	return found


## Icon `id` (a material, credits, fuel, power, o2, hull, a mode or a palette category) drawn into `r`.
static func icon(cv: CanvasItem, id: String, r: Rect2, mod := Color.WHITE) -> void:
	var a = icon_art(id)
	if a != null:
		cv.draw_texture_rect_region(a[0], r, a[1], mod)
		return
	_glyph(cv, id, r, mod)


## The flat stand-in for an icon, on a 16-unit grid.
static func _glyph(cv: CanvasItem, id: String, r: Rect2, mod: Color) -> void:
	var u := r.size / 16.0
	var o := r.position
	var p := func(pts: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for q in pts:
			out.append(o + Vector2(q[0], q[1]) * u)
		return out
	var poly := func(pts: Array, col: Color) -> void:
		var pv: PackedVector2Array = p.call(pts)
		cv.draw_colored_polygon(pv, col * mod)
		pv.append(pv[0])
		cv.draw_polyline(pv, (col.darkened(0.6)) * mod, 1.0)
	var box := func(x: float, y: float, w: float, h: float, col: Color) -> void:
		cv.draw_rect(Rect2(o + Vector2(x, y) * u, Vector2(w, h) * u), col * mod)
	var col: Color = MATERIAL_COLORS.get(id, EDGE)
	match id:
		"scrap":
			poly.call([[2, 9], [5, 4], [9, 3], [13, 6], [14, 11], [10, 14], [4, 13]], col)
			box.call(6, 6, 3, 2, col.lightened(0.35))
		"copper", "titanium":
			poly.call([[1, 12], [3, 6], [13, 6], [15, 12]], col)
			box.call(4, 7, 8, 1.5, col.lightened(0.4))
		"polymer":
			poly.call([[8, 1], [14, 4.5], [14, 11.5], [8, 15], [2, 11.5], [2, 4.5]], col)
			box.call(6, 5, 4, 1.5, Color.WHITE)
		"silicon":
			poly.call([[8, 1], [15, 8], [8, 15], [1, 8]], col)
			cv.draw_line(o + Vector2(4.5, 4.5) * u, o + Vector2(11.5, 11.5) * u, col.lightened(0.4) * mod, 1.0)
			cv.draw_line(o + Vector2(11.5, 4.5) * u, o + Vector2(4.5, 11.5) * u, col.lightened(0.4) * mod, 1.0)
		"crystal":
			poly.call([[8, 1], [13, 6], [8, 15], [3, 6]], col)
			poly.call([[8, 1], [10, 6], [8, 15], [6, 6]], col.lightened(0.3))
		"steel", "alloy":  # a bar with a bright edge (no art yet: the smelter materials are drawn by code)
			poly.call([[2, 11], [4, 6], [14, 6], [12, 11]], col)
			poly.call([[4, 6], [6, 3], [14, 3], [14, 6]], col.lightened(0.3))
			box.call(5, 8, 6, 1.2, col.lightened(0.45))
		"conductor":  # a coil
			for k in 3:
				cv.draw_arc(o + Vector2(8, 4.5 + k * 3.2) * u, 5.0 * u.x, 0.0, PI, 10, col * mod, 1.6 * u.x)
				cv.draw_arc(o + Vector2(8, 6.1 + k * 3.2) * u, 5.0 * u.x, PI, TAU, 10, col.darkened(0.3) * mod, 1.6 * u.x)
		"glass_lattice":  # a net of panes
			poly.call([[8, 1], [15, 8], [8, 15], [1, 8]], col.darkened(0.2))
			cv.draw_line(o + Vector2(4.5, 4.5) * u, o + Vector2(11.5, 11.5) * u, col.lightened(0.5) * mod, 1.0)
			cv.draw_line(o + Vector2(11.5, 4.5) * u, o + Vector2(4.5, 11.5) * u, col.lightened(0.5) * mod, 1.0)
			cv.draw_line(o + Vector2(8, 2.5) * u, o + Vector2(8, 13.5) * u, col.lightened(0.5) * mod, 1.0)
		"plasma_cell", "nanite_paste":
			box.call(5, 2, 6, 12, col.darkened(0.2))
			box.call(6, 4, 4, 8, col)
			box.call(6, 1, 4, 1.5, EDGE)
		"credits":
			cv.draw_circle(o + Vector2(8, 8) * u, 6.5 * u.x, col.darkened(0.45) * mod)
			cv.draw_circle(o + Vector2(8, 8) * u, 5.5 * u.x, col * mod)
			cv.draw_circle(o + Vector2(8, 8) * u, 3.0 * u.x, col.darkened(0.25) * mod)
		"fuel":
			poly.call([[3, 4], [10, 4], [13, 7], [13, 15], [3, 15]], col)
			box.call(4, 1, 4, 3, EDGE_DIM)
			box.call(5, 8, 6, 4, col.darkened(0.35))
		"missile":
			poly.call([[8, 1], [11, 5], [11, 12], [13, 15], [3, 15], [5, 12], [5, 5]], col)
		"power":
			poly.call([[10, 1], [3, 9], [7.5, 9], [6, 15], [13, 6.5], [8.5, 6.5]], GOOD)
		"o2":
			cv.draw_circle(o + Vector2(6, 9) * u, 4.5 * u.x, SHIELD * mod)
			cv.draw_circle(o + Vector2(11.5, 5) * u, 2.5 * u.x, SHIELD.lightened(0.3) * mod)
			cv.draw_circle(o + Vector2(5, 8) * u, 1.5 * u.x, Color(1, 1, 1, 0.7) * mod)
		"hull":
			poly.call([[8, 1], [14, 3], [13, 10], [8, 15], [3, 10], [2, 3]], AMBER)
			poly.call([[8, 4], [11, 5], [10.5, 9.5], [8, 12], [5.5, 9.5], [5, 5]], AMBER.darkened(0.35))
		"wrench":  # damaged blocks to fix (the top bar)
			poly.call([[2.5, 13], [4, 14.5], [10.5, 8], [9, 6.5]], AMBER)
			cv.draw_circle(o + Vector2(10.5, 5.5) * u, 4.0 * u.x, AMBER)
			poly.call([[10.5, 5.5], [15.5, 0.5], [15.5, 6.5]], AMBER.darkened(0.75))
		"heat":
			poly.call([[8, 1], [12, 7], [12, 11], [8, 15], [4, 11], [4, 7]], Color("#ff8a1e"))
			poly.call([[8, 7], [10, 11], [8, 14], [6, 11]], Color("#ffd23a"))
		"crew":
			cv.draw_circle(o + Vector2(8, 5) * u, 3.2 * u.x, EDGE * mod)
			poly.call([[2, 15], [4, 10], [12, 10], [14, 15]], EDGE)
		"build":
			poly.call([[2, 12], [9, 5], [11, 7], [4, 14]], AMBER)
			poly.call([[8, 2], [13, 2], [15, 4], [15, 7], [12, 7], [10, 5]], EDGE)
		"play":
			poly.call([[4, 2], [14, 8], [4, 14]], GOOD)
		"map":
			for e in [[[3, 12], [8, 4]], [[8, 4], [13, 10]], [[3, 12], [13, 10]]]:
				cv.draw_line(o + Vector2(e[0][0], e[0][1]) * u, o + Vector2(e[1][0], e[1][1]) * u, EDGE_DIM * mod, 1.5)
			for q in [[3, 12], [8, 4], [13, 10]]:
				cv.draw_circle(o + Vector2(q[0], q[1]) * u, 2.2 * u.x, (AMBER if q == [8, 4] else EDGE) * mod)
		"shields":
			cv.draw_arc(o + Vector2(8, 10) * u, 6.5 * u.x, PI, TAU, 12, SHIELD * mod, 2.0 * u.x)
			cv.draw_arc(o + Vector2(8, 10) * u, 3.5 * u.x, PI, TAU, 10, SHIELD.lightened(0.3) * mod, 1.5 * u.x)
			box.call(6, 10, 4, 4, EDGE)
		"crafting":
			for i in 8:
				var a := i * TAU / 8.0
				cv.draw_rect(Rect2(o + (Vector2(8, 8) + Vector2.from_angle(a) * 5.5) * u - u * 1.5, u * 3.0), EDGE * mod)
			cv.draw_circle(o + Vector2(8, 8) * u, 5.0 * u.x, EDGE * mod)
			cv.draw_circle(o + Vector2(8, 8) * u, 2.2 * u.x, PANEL_BG * mod)
		"help":
			cv.draw_circle(o + Vector2(8, 8) * u, 7.0 * u.x, SHIELD.darkened(0.3) * mod)
			cv.draw_string(bold(), o + Vector2(4.6, 12.6) * u, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, int(12.0 * u.y), TEXT * mod)
		"pause":
			box.call(4, 3, 3, 10, AMBER)
			box.call(9, 3, 3, 10, AMBER)
		"structure":
			for row in 3:
				for k in 3:
					box.call(1 + k * 5 - (2.5 if row == 1 else 0.0), 2 + row * 4.5, 4.5, 3.5, Color("#9aa3b5") if (row + k) % 2 == 0 else Color("#7d8798"))
			box.call(0, 0, 1, 16, PANEL_BG)
			box.call(15, 0, 1, 16, PANEL_BG)
		"shapes":
			poly.call([[2, 14], [14, 2], [14, 14]], Color("#9aa3b5"))
		"systems":
			box.call(2, 2, 12, 12, Color("#5b6577"))
			cv.draw_circle(o + Vector2(8, 8) * u, 3.5 * u.x, Color("#f2c14e") * mod)
		"weapons":
			box.call(3, 8, 10, 6, Color("#7d8798"))
			box.call(7, 1, 2.5, 8, EDGE)
			box.call(5, 10, 6, 2, BAD)
		"engines":
			poly.call([[3, 2], [13, 2], [11, 9], [5, 9]], Color("#7d8798"))
			poly.call([[5, 9], [11, 9], [8, 15]], Color("#ff8a1e"))
		"utility":
			box.call(6.5, 2, 3, 12, GOOD)
			box.call(2, 6.5, 12, 3, GOOD)
		"st_damage":  # a burst
			poly.call([[8, 1], [10, 6], [15, 8], [10, 10], [8, 15], [6, 10], [1, 8], [6, 6]], Color("#ff6a4a"))
			box.call(7, 7, 2, 2, Color("#ffe0a0"))
		"st_rate":  # three chevrons
			for k in 3:
				cv.draw_polyline(p.call([[3 + k * 3.5, 3], [7 + k * 3.5, 8], [3 + k * 3.5, 13]]), Color("#f2c14e") * mod, 2.0 * u.x)
		"st_range":  # a line between two ticks, an arrow head
			box.call(1, 4, 1.5, 8, EDGE)
			box.call(1, 7.2, 11, 1.6, EDGE)
			poly.call([[15, 8], [10.5, 4.5], [10.5, 11.5]], EDGE)
		"st_layers":  # nested arcs
			cv.draw_arc(o + Vector2(8, 12) * u, 7.0 * u.x, PI, TAU, 12, SHIELD * mod, 1.6 * u.x)
			cv.draw_arc(o + Vector2(8, 12) * u, 4.5 * u.x, PI, TAU, 10, SHIELD.lightened(0.25) * mod, 1.6 * u.x)
			cv.draw_arc(o + Vector2(8, 12) * u, 2.0 * u.x, PI, TAU, 8, SHIELD.lightened(0.5) * mod, 1.6 * u.x)
		"st_recharge":  # a circular arrow
			cv.draw_arc(o + Vector2(8, 8) * u, 5.0 * u.x, -0.4, TAU - 1.2, 14, SHIELD * mod, 2.0 * u.x)
			poly.call([[11, 1.5], [14.5, 5], [9.5, 6.5]], SHIELD)
		"st_thrust":  # a flame under a bar
			box.call(3, 2, 10, 3, Color("#7d8798"))
			poly.call([[4, 5], [12, 5], [8, 15]], Color("#ff8a1e"))
			poly.call([[6.5, 5], [9.5, 5], [8, 10]], Color("#ffd23a"))
		"st_hp":  # a plus
			box.call(6, 2, 4, 12, BAD)
			box.call(2, 6, 12, 4, BAD)
		"st_mass":  # a weight
			poly.call([[5, 4], [11, 4], [14, 14], [2, 14]], Color("#8a93a3"))
			cv.draw_arc(o + Vector2(8, 4) * u, 2.5 * u.x, PI, TAU, 8, EDGE * mod, 1.4 * u.x)
		"aim_fixed":  # one line forward
			box.call(7, 3, 2, 12, EDGE)
			poly.call([[8, 0.5], [12, 5], [4, 5]], EDGE)
		"aim_swivel":  # a narrow fan
			poly.call([[8, 14], [2, 3], [14, 3]], Color("#f2c14e"))
			poly.call([[8, 14], [5.5, 5], [10.5, 5]], Color("#f2c14e").lightened(0.4))
		"aim_turret":  # a ring with a barrel
			cv.draw_arc(o + Vector2(8, 9) * u, 5.5 * u.x, 0.0, TAU, 16, GOOD * mod, 1.6 * u.x)
			box.call(7, 1, 2, 8, GOOD)
		"item":  # a crate
			box.call(2, 4, 12, 10, Color("#8a93a3"))
			box.call(2, 4, 12, 2.5, Color("#aab3c2"))
			cv.draw_rect(Rect2(o + Vector2(2, 4) * u, Vector2(12, 10) * u), Color("#3b4452") * mod, false, 1.0)
		"cargo":
			box.call(2, 3, 12, 11, Color("#8a6a45"))
			cv.draw_line(o + Vector2(2, 3) * u, o + Vector2(14, 14) * u, Color("#5a4228") * mod, 1.5)
			cv.draw_line(o + Vector2(14, 3) * u, o + Vector2(2, 14) * u, Color("#5a4228") * mod, 1.5)
			cv.draw_rect(Rect2(o + Vector2(2, 3) * u, Vector2(12, 11) * u), Color("#5a4228") * mod, false, 1.0)
		_:
			cv.draw_circle(o + Vector2(8, 8) * u, 5.5 * u.x, col * mod)
