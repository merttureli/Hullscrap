extends Control
## The selection card, on the right in build mode: everything about the card under the mouse in the palette, else
## about the tool in hand (palette.gd info()): name, line, tier, a big picture, what it does, its stats, what its type
## means, the quirk and abilities, the lore, the recipe and where it can go, and in red why it can't be placed now.
## Its height follows what it says; build_mode.gd keeps the rules. Draws only.

const Palette = preload("res://scripts/build/palette.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Thumbs = preload("res://scripts/ui/thumbs.gd")

const PAD := 14.0
const TITLE := 18
const BODY := 12
const LINE := 17.0
const PIC_H := 112.0
const PIC_MIN := 40.0  ## the picture shrinks to this when the words need the room
const LABEL_W := 96.0

var hud: Control
var _clock := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(dt: float) -> void:
	_clock += dt
	if visible:
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	hud.pass_release(e)
	if UiKit.is_wheel(e):
		accept_event()  # nothing to scroll here, and the world behind must not zoom


## The card shown: the palette card under the mouse, else the tool in hand ({} when there is neither).
func entry() -> Dictionary:
	if hud == null or hud.build == null or hud.build.ship == null:
		return {}
	var e: Dictionary = hud.palette.hovered() if hud.palette != null else {}
	return e if not e.is_empty() else hud.build.selected_entry()


## What it says about entry(): palette.gd info(), or {} for nothing.
func info() -> Dictionary:
	var e := entry()
	return Palette.info(e, hud.build.ship, hud.build.rot) if not e.is_empty() else {}


## The blocks top to bottom, wrapped to the card's width: [kind, height, data].
func blocks() -> Array:
	var e := entry()
	if e.is_empty():
		return [["text", LINE * 2.0, {"lines": ["Pick something in the palette."], "color": UiKit.DIM_TEXT}]]
	var inf := Palette.info(e, hud.build.ship, hud.build.rot)
	var w := size.x - 2.0 * PAD
	var out := []
	var title := UiKit.wrap(inf["title"], w, TITLE, UiKit.bold())
	out.append(["title", title.size() * 22.0 + 4.0, {"lines": title}])
	out.append(["chips", 26.0, {}])
	out.append(["pic", PIC_H + 10.0, {"h": PIC_H}])
	if inf["does"] != "":
		_text(out, inf["does"], w, UiKit.TEXT)
	var rows := []
	for row in inf["rows"]:
		var vl := UiKit.wrap(str(row[1]), w - LABEL_W, BODY)
		rows.append([row[0], vl])
	var rh := 0.0
	for row in rows:
		rh += row[1].size() * LINE
	out.append(["rows", rh + 6.0, {"rows": rows}])
	if not e["ok"]:
		var why := str(e["why"])
		_text(out, why.substr(0, 1).to_upper() + why.substr(1), w, UiKit.BAD.lightened(0.15))
	if not inf["kinds"].is_empty():
		_head(out, "WHAT IT MEANS")
		for k in inf["kinds"]:
			_text(out, k, w, UiKit.TEXT)
	if inf["quirk"] != "":
		_text(out, inf["quirk"], w, UiKit.AMBER)
	if not inf["abilities"].is_empty():
		_head(out, "ABILITIES")
		for a in inf["abilities"]:
			_text(out, a, w, UiKit.SHIELD.lightened(0.3))
	if inf["blurb"] != "":
		_text(out, inf["blurb"], w, UiKit.DIM_TEXT)
	if inf["recipe"] != "":
		_head(out, "RECIPE")
		_text(out, inf["recipe"], w, UiKit.TEXT)
	if inf["place"] != "":
		_head(out, "PLACEMENT")
		_text(out, inf["place"], w, UiKit.TEXT)
	var over := _sum(out) - available_height()
	if over > 0.0:  # a long description: the picture gives up room so the recipe and placement still show
		var h := maxf(PIC_MIN, PIC_H - over)
		out[2] = ["pic", h + 10.0, {"h": h}]
	return out


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


func _head(out: Array, s: String) -> void:
	out.append(["head", 20.0, {"text": s}])


## The height the card wants for what it says now.
func wanted_height() -> float:
	return _sum(blocks())


func _draw() -> void:
	if hud == null or hud.build == null or hud.build.ship == null:
		return
	UiKit.panel(self, Rect2(Vector2.ZERO, size))
	var e := entry()
	var y := PAD
	var x := PAD
	var w := size.x - 2.0 * PAD
	for bl in blocks():
		if y + bl[1] > size.y - 4.0:
			break  # out of room: the rest is cut
		var d: Dictionary = bl[2]
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
			"rows":
				var yy := y + 13.0
				for row in d["rows"]:
					UiKit.text(self, row[0], Vector2(x, yy), BODY, UiKit.DIM_TEXT)
					for l in row[1]:
						UiKit.text(self, l, Vector2(x + LABEL_W, yy), BODY, UiKit.TEXT)
						yy += LINE
			"head":
				UiKit.text(self, d["text"], Vector2(x, y + 15.0), 11, UiKit.EDGE_DIM.lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiKit.bold())
				draw_line(Vector2(x + UiKit.text_width(d["text"], 11, UiKit.bold()) + 6.0, y + 11.0), Vector2(x + w, y + 11.0), UiKit.EDGE_DIM, 1.0)
			"text":
				for i in d["lines"].size():
					UiKit.text(self, d["lines"][i], Vector2(x, y + 13.0 + i * LINE), BODY, d["color"])
		y += bl[1]


## The line in its colour, the tier, and Unique / Structure.
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
