extends Control
## The selection card, on the right in build mode: the card under the mouse in the palette, else the tool in hand
## (palette.gd info()). Top to bottom: name; the line, tier and how many are held; the picture; what it does in one line;
## its keyword chips (a coloured word per mechanic: LASER, AUTO, FIRE 5% ...; the mouse on one says what it does); a
## compact grid of its stats; one line of lore; its cost with the cargo icons. Its height follows what it says;
## build_mode.gd keeps the rules. Draws only.

const Palette = preload("res://scripts/build/palette.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Thumbs = preload("res://scripts/ui/thumbs.gd")

const PAD := 14.0
const TITLE := 18
const BODY := 12
const LINE := 17.0
const PIC_H := 96.0
const PIC_MIN := 40.0  ## the picture shrinks to this when the words need the room
const LABEL_W := 62.0  ## a stat's label column
const CHIP := 11  ## font size of a keyword chip
const LINGER := 0.8  ## s a palette card stays on show after the mouse left it, so the mouse can reach its chips

var hud: Control
var hover_kw := {}  ## the keyword chip under the mouse ({} for none)
var hover_rect := Rect2()  ## and where it is (card px)
var _clock := 0.0
var _seen := ""  # key of the palette card last under the mouse
var _seen_at := -10.0  # and when
var _over := false  # the mouse is on the card


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _over = true)
	mouse_exited.connect(func():
		_over = false
		_seen = ""
		hover_kw = {})


func _process(dt: float) -> void:
	_clock += dt
	if visible:
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	hud.pass_release(e)
	if UiKit.is_wheel(e):
		accept_event()  # nothing to scroll here, and the world behind must not zoom
	if e is InputEventMouseMotion:
		point_at(e.position)


## The mouse is at card px `p`: the keyword chip under it, if any, is the one to explain.
func point_at(p: Vector2) -> void:
	hover_kw = {}
	for c in chips():
		if c[0].has_point(p):
			hover_kw = c[1]
			hover_rect = c[0]


## The card shown: the palette card under the mouse (or just left, or the mouse is on this card), else the tool in hand
## ({} when there is neither).
func entry() -> Dictionary:
	if hud == null or hud.build == null or hud.build.ship == null:
		return {}
	var e: Dictionary = hud.palette.hovered() if hud.palette != null else {}
	if not e.is_empty():
		_seen = str(e["key"])
		_seen_at = _clock
		return e
	if _seen != "" and (_over or _clock - _seen_at < LINGER) and hud.palette != null:
		for c in hud.palette.entries():
			if c["key"] == _seen:
				return c
	return hud.build.selected_entry()


## What it says about entry(): palette.gd info(), or {} for nothing.
func info() -> Dictionary:
	var e := entry()
	return Palette.info(e, hud.build.ship, hud.build.rot, hud.build.held_angle()) if not e.is_empty() else {}


## The blocks top to bottom, wrapped to the card's width: [kind, height, data].
func blocks() -> Array:
	var e := entry()
	if e.is_empty():
		return [["text", LINE * 2.0, {"lines": ["Pick a part."], "color": UiKit.DIM_TEXT}]]
	var inf := Palette.info(e, hud.build.ship, hud.build.rot, hud.build.held_angle())
	var w := size.x - 2.0 * PAD
	var out := []
	var title := UiKit.wrap(inf["title"], w, TITLE, UiKit.bold())
	out.append(["title", title.size() * 22.0 + 4.0, {"lines": title}])
	out.append(["chips", 26.0, {}])
	out.append(["pic", PIC_H + 10.0, {"h": PIC_H}])
	if inf["what"] != "":
		_text(out, inf["what"], w, UiKit.TEXT)
	if not inf["keywords"].is_empty():
		var lay := UiKit.chip_layout(inf["keywords"], Vector2.ZERO, w, CHIP)
		out.append(["kws", lay[lay.size() - 1][0].end.y + 6.0, {"kws": inf["keywords"]}])
	if not inf["stats"].is_empty():
		var grid := _grid(inf["stats"], w)
		out.append(["grid", grid.size() * LINE + 6.0, {"rows": grid}])
	if inf["lore"] != "":
		var lines := UiKit.wrap(inf["lore"], w, BODY, UiKit.italic())
		lines = lines.slice(0, 2)
		out.append(["lore", lines.size() * LINE + 4.0, {"lines": lines}])
	if not inf["cost"].is_empty() or inf["note"] != "":
		var cost := _cost(inf, e, w)
		out.append(["cost", cost["h"], cost])
	var over := _sum(out) - available_height()
	if over > 0.0:  # a long description: the picture gives up room so the cost still shows
		var h := maxf(PIC_MIN, PIC_H - over)
		out[2] = ["pic", h + 10.0, {"h": h}]
	return out


## The stats in two columns: rows of [[label, value, column]]; a value too long for its column takes a row of its own.
func _grid(stats: Array, w: float) -> Array:
	var col_w := w / 2.0
	var rows := []
	var row := []
	for s in stats:
		var wide := UiKit.text_width(str(s[1]), BODY) > col_w - LABEL_W - 6.0
		if wide or row.size() == 2:
			if not row.is_empty():
				rows.append(row)
			row = []
		if wide:
			rows.append([[s[0], s[1], 0]])
		else:
			row.append([s[0], s[1], row.size()])
	if not row.is_empty():
		rows.append(row)
	return rows


## The cost line: "Cost", each material with its icon, the fabricator level, and the note (how to get one) on the same
## line when it fits, else under it: {mats ([[id, n]]), level, per, note, wrapped (the note is on its own line), h}.
func _cost(inf: Dictionary, e: Dictionary, w: float) -> Dictionary:
	var mats := []
	var x := 40.0
	for m in inf["cost"]:
		mats.append([m, int(inf["cost"][m])])
		x += 14.0 + UiKit.text_width(str(inf["cost"][m]), BODY) + 12.0
	var tail: String = (" " + str(inf["per"])) if inf["per"] != "" else ""
	if int(inf["level"]) > 1:
		tail += "  Fab L%d" % int(inf["level"])
	x += UiKit.text_width(tail, BODY)
	var note: String = inf["note"]
	var wrapped := note != "" and x + 12.0 + UiKit.text_width(note, BODY) > w
	return {"mats": mats, "level": inf["level"], "tail": tail, "note": note, "wrapped": wrapped, "none": mats.is_empty(),
		"h": LINE + 8.0 + (LINE if wrapped else 0.0)}


## The tallest the card may be: the screen under the top bar, with the margins (hud.gd places it so).
func available_height() -> float:
	return (get_viewport_rect().size.y if is_inside_tree() else 900.0) - 56.0


func _sum(bl: Array) -> float:
	var h := 2.0 * PAD
	for b in bl:
		h += b[1]
	return h


func _text(out: Array, s: String, w: float, col: Color) -> void:
	var lines := UiKit.wrap(s, w, BODY)
	out.append(["text", lines.size() * LINE + 4.0, {"lines": lines, "color": col}])


## The height the card wants for what it says now.
func wanted_height() -> float:
	return _sum(blocks())


## Every block with its top: [[kind, y, height, data]].
func placed() -> Array:
	var out := []
	var y := PAD
	for bl in blocks():
		out.append([bl[0], y, bl[1], bl[2]])
		y += bl[1]
	return out


## The keyword chips of the card: [[Rect2 (card px), keyword]].
func chips() -> Array:
	for b in placed():
		if b[0] == "kws":
			return UiKit.chip_layout(b[3]["kws"], Vector2(PAD, b[1] + 2.0), size.x - 2.0 * PAD, CHIP)
	return []


func _draw() -> void:
	if hud == null or hud.build == null or hud.build.ship == null:
		return
	UiKit.panel(self, Rect2(Vector2.ZERO, size))
	var e := entry()
	var x := PAD
	var w := size.x - 2.0 * PAD
	for bl in placed():
		var y: float = bl[1]
		if y + bl[2] > size.y - 4.0:
			break  # out of room: the rest is cut
		var d: Dictionary = bl[3]
		match bl[0]:
			"title":
				for i in d["lines"].size():
					UiKit.text(self, d["lines"][i], Vector2(x, y + 18.0 + i * 22.0), TITLE, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiKit.bold())
			"chips":
				_draw_chips(e, Vector2(x, y + 2.0))
			"pic":
				var r := Rect2(x, y, w, d["h"])
				UiKit.inset(self, r)
				Thumbs.draw(self, e, hud.build.ship, r.grow(-8), _clock)
				if not e["ok"]:
					draw_rect(r, Color(0.07, 0.09, 0.12, 0.5))
			"kws":
				for c in UiKit.chip_layout(d["kws"], Vector2(x, y + 2.0), w, CHIP):
					UiKit.keyword_chip(self, c[0], c[1], CHIP, c[1] == hover_kw)
			"grid":
				var yy: float = y + 13.0
				for row in d["rows"]:
					for it in row:
						var cx: float = x + it[2] * w / 2.0
						UiKit.text(self, it[0], Vector2(cx, yy), BODY, UiKit.DIM_TEXT)
						UiKit.text(self, it[1], Vector2(cx + LABEL_W, yy), BODY, UiKit.TEXT)
					yy += LINE
			"lore":
				for i in d["lines"].size():
					UiKit.text(self, d["lines"][i], Vector2(x, y + 13.0 + i * LINE), BODY, UiKit.DIM_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiKit.italic())
			"cost":
				_draw_cost(d, Vector2(x, y), w, e)
			"text":
				for i in d["lines"].size():
					UiKit.text(self, d["lines"][i], Vector2(x, y + 13.0 + i * LINE), BODY, d["color"])
	if not hover_kw.is_empty():
		var lines := UiKit.wrap(hover_kw["hover"], size.x - 2.0 * PAD - 16.0, 12)
		var tw := 16.0
		for l in lines:
			tw = maxf(tw, UiKit.text_width(l, 12) + 16.0)
		UiKit.note(self, lines, Vector2(minf(hover_rect.position.x, size.x - 4.0 - tw), hover_rect.end.y + 4.0), hover_kw["color"])


## "Cost", the materials with their cargo icons (red when the cargo is short and it is not a part already held), the level.
func _draw_cost(d: Dictionary, at: Vector2, w: float, e: Dictionary) -> void:
	var base := at.y + 14.0
	var short: Dictionary = {}
	if e["kind"] != "part" or e["count"] == 0:
		short = hud.build.ship.inventory.missing(_mats(d))
	var x := at.x
	if not d["none"]:
		UiKit.text(self, "Cost", Vector2(x, base), BODY, UiKit.DIM_TEXT)
		x += 40.0
		for m in d["mats"]:
			UiKit.icon(self, m[0], Rect2(x, base - 12.0, 14, 14))
			x += 16.0
			var t := str(m[1])
			UiKit.text(self, t, Vector2(x, base), BODY, UiKit.BAD.lightened(0.2) if short.has(m[0]) else UiKit.TEXT)
			x += UiKit.text_width(t, BODY) + 12.0
		UiKit.text(self, str(d["tail"]).strip_edges(), Vector2(x - 6.0, base), BODY, UiKit.DIM_TEXT)
	if d["note"] != "":
		if d["wrapped"]:
			UiKit.text(self, d["note"], Vector2(at.x, base + LINE), BODY, UiKit.AMBER)
		else:
			UiKit.text(self, d["note"], Vector2(at.x, base), BODY, UiKit.AMBER, HORIZONTAL_ALIGNMENT_LEFT if d["none"] else HORIZONTAL_ALIGNMENT_RIGHT, w)


func _mats(d: Dictionary) -> Dictionary:
	var out := {}
	for m in d["mats"]:
		out[m[0]] = m[1]
	return out


## The line in its colour, the tier, and Unique / Structure; how many are held on the right.
func _draw_chips(e: Dictionary, at: Vector2) -> void:
	var x := at.x
	var line: String = e["line"]
	var def: Dictionary = hud.build.ship.components.def(e["id"]) if e["kind"] == "part" else {}
	var shown := line if line != "unique" else str(def.get("line", "standard"))
	x += UiKit.chip(self, Palette.LINE_NAMES.get(shown, shown.capitalize()), Vector2(x, at.y), UiKit.LINE_COLORS.get(shown, UiKit.EDGE)) + 6.0
	if int(e["tier"]) > 0:
		x += UiKit.chip(self, "Mk%d" % int(e["tier"]), Vector2(x, at.y), UiKit.EDGE) + 6.0
	if line == "unique":
		x += UiKit.chip(self, "Unique", Vector2(x, at.y), UiKit.LINE_COLORS["unique"]) + 6.0
	if e["kind"] != "part":
		x += UiKit.chip(self, {"item": "Cargo", "cable": "Power"}.get(e["kind"], "Structure"), Vector2(x, at.y), UiKit.DIM_TEXT) + 6.0
	if e["kind"] in ["part", "item"]:
		UiKit.text(self, "x%d held" % e["count"], Vector2(at.x, at.y + 14.0), BODY, UiKit.TEXT if e["count"] > 0 else UiKit.BAD.lightened(0.2), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 2.0 * PAD)
