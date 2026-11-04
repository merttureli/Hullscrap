extends RefCounted
## The recipe card of the craft panel: what a part is called, what it does (data/describe.json), its key stats, its materials (green when the hold has
## them, red when not) and why it cannot be queued now. data() holds the words, draw() puts them on a canvas, so tests read the words, not pixels.
## The build palette's hover card is hud_card.gd, which says the same things for a part in the build view.

const Describe = preload("res://scripts/ui/describe.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const PAD := 10.0
const LINE := 17.0
const MAX_STATS := 8
const BG := Color("#1f2630")
const EDGE := Color("#cfd6df")
const TEXT := Color("#eef2f7")
const DIM_TEXT := Color("#97a3b3")
const AMBER := Color("#e1a136")
const GOOD := Color("#6bd34a")
const BAD := Color("#e0413b")


## The card of recipe `id` on `ship`: {title, what, stats [[label, value]], mats [[name, need, have, ok]], level, reason}. `why` is the reason it cannot be queued ("" when it can).
static func data(id: String, ship, why: String) -> Dictionary:
	var rec: Dictionary = ship.crafting.def(id)
	var item := str(rec["output"]["item"])
	var d := Describe.of(item, ship)
	var stats := []
	for r in d["stats"]:
		if str(r[0]) != "Size" and stats.size() < MAX_STATS:
			stats.append([str(r[0]), str(r[1])])
	var mats := []
	for m in rec["materials"]:
		var have: int = ship.inventory.count(m)
		mats.append([ship.crafting.name_of(m), int(rec["materials"][m]), have, have >= int(rec["materials"][m])])
	return {"title": ship.crafting.name_of(item, ship.components), "what": str(d["what"]), "stats": stats, "mats": mats, "level": int(rec["fab_level"]), "reason": why}


## The height the card needs at `width`.
static func height(d: Dictionary, width: float) -> float:
	var h := 2.0 * PAD + 24.0
	if d["what"] != "":
		h += UiKit.wrap(d["what"], width - 2.0 * PAD, 13).size() * LINE + 4.0
	h += ceili(d["stats"].size() / 2.0) * LINE + 6.0
	h += LINE + 6.0
	if d["reason"] != "":
		h += UiKit.wrap(d["reason"], width - 2.0 * PAD, 13).size() * LINE
	return h


## Draw the card with its top left at `at`; returns its rect.
static func draw(cv: CanvasItem, at: Vector2, width: float, d: Dictionary) -> Rect2:
	var r := Rect2(at, Vector2(width, height(d, width)))
	cv.draw_rect(r, BG)
	cv.draw_rect(r, EDGE, false, 2.0)
	var f := ThemeDB.fallback_font
	var x := r.position.x + PAD
	var y := r.position.y + PAD + 14.0
	cv.draw_string(f, Vector2(x, y), str(d["title"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, AMBER)
	y += 10.0
	if d["what"] != "":
		for l in UiKit.wrap(d["what"], width - 2.0 * PAD, 13):
			y += LINE
			cv.draw_string(f, Vector2(x, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
		y += 4.0
	var col_w := (width - 2.0 * PAD) / 2.0
	for i in d["stats"].size():
		if i % 2 == 0:
			y += LINE
		var s: Array = d["stats"][i]
		var sx: float = x + (i % 2) * col_w
		cv.draw_string(f, Vector2(sx, y), str(s[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM_TEXT)
		cv.draw_string(f, Vector2(sx + 58.0, y), str(s[1]), HORIZONTAL_ALIGNMENT_LEFT, col_w - 62.0, 12, TEXT)
	y += 6.0 + LINE
	var mx := x
	for m in d["mats"]:
		var seg := "%s %d" % [m[0], m[1]] if m[3] else "%s %d/%d" % [m[0], m[2], m[1]]
		cv.draw_string(f, Vector2(mx, y), seg, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOOD if m[3] else BAD)
		mx += UiKit.text_width(seg, 13) + 12.0
	if d["reason"] != "":
		y += 6.0
		for l in UiKit.wrap(d["reason"], width - 2.0 * PAD, 13):
			y += LINE
			cv.draw_string(f, Vector2(x, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, AMBER)
	return r
