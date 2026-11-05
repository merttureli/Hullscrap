extends RefCounted
## The picture card of the build palette and the crafting panel: the item's real sprite (thumbs.gd), two or three figures as
## small icon-and-number pairs, its cost as material icons with counts (red when short) or how many are held, a number key, a tag
## (NEW, x3) and a gun's aim mark. It carries NO NAME: the name, the description and the full stats are in the hover card
## (hud_card.gd in the build view, part_card.gd in the crafting panel). The caller builds a spec, labels() lists every word the
## card prints (what tests read), draw() paints it.
## spec: {entry (thumbs.gd's card: kind, id ...), line, stats [{icon, text, what}], aim ("" or fixed/swivel/turret), cost {id: n}, short {id: n}
##        (what is missing), held (-1: not a held part, else how many), tags [text], key (1..9, 0 none), meta (text), meta_bad}

const Thumbs = preload("res://scripts/ui/thumbs.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const PAD := 7.0
const FONT := 11
const ROW := 15.0  ## a row of figures or of cost
const ICON := 12.0
const MIN_PIC := 40.0


## Every string the card prints, in the order it prints them.
static func labels(spec: Dictionary) -> Array:
	var out := []
	if int(spec.get("key", 0)) > 0:
		out.append(str(spec["key"]))
	out.append_array(spec.get("tags", []))
	for s in spec.get("stats", []):
		out.append(str(s["text"]))
	var cost: Dictionary = spec.get("cost", {})
	for m in cost:
		out.append(str(cost[m]))
	if int(spec.get("held", -1)) >= 0:
		out.append("x%d" % int(spec["held"]))
	if str(spec.get("meta", "")) != "":
		out.append(str(spec["meta"]))
	return out


## The figures laid out in rows of width `w`: [[pair index, x, row]], and how many rows.
static func _flow(stats: Array, w: float) -> Dictionary:
	var at := []
	var x := 0.0
	var row := 0
	for i in stats.size():
		var pw := ICON + 2.0 + UiKit.text_width(str(stats[i]["text"]), FONT) + 7.0
		if x > 0.0 and x + pw - 7.0 > w:
			x = 0.0
			row += 1
		at.append([i, x, row])
		x += pw
	return {"at": at, "rows": row + 1 if not stats.is_empty() else 0}


## Draw the card in `r` (for `ship`, whose thumbs need its grid); `t`: seconds, for the art's loops.
static func draw(cv: CanvasItem, r: Rect2, ship, spec: Dictionary, selected: bool, hot: bool, t := 0.0) -> void:
	UiKit.card(cv, r, str(spec.get("line", "standard")), selected, hot)
	var x := r.position.x + PAD
	var w := r.size.x - 2.0 * PAD
	var stats: Array = spec.get("stats", [])
	var fl := _flow(stats, w)
	var foot: float = ROW + 2.0 + float(fl["rows"]) * ROW  # the figures and the cost row under the picture
	var pic := Rect2(Vector2(x, r.position.y + PAD), Vector2(w, maxf(MIN_PIC, r.size.y - 2.0 * PAD - foot)))
	Thumbs.draw(cv, spec["entry"], ship, pic, t)
	if int(spec.get("key", 0)) > 0:
		var k := Rect2(r.position + Vector2(4, 4), Vector2(15, 15))
		cv.draw_rect(k, Color(0, 0, 0, 0.7))
		cv.draw_rect(k, UiKit.EDGE_DIM, false, 1.0)
		cv.draw_string(UiKit.bold(), k.position + Vector2(4.0, 11.5), str(spec["key"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.AMBER if selected else UiKit.TEXT)
	var tx := r.end.x - 4.0
	for tag in spec.get("tags", []):  # chips in the top right corner, right to left
		var tw := UiKit.text_width(tag, 10, UiKit.bold()) + 8.0
		tx -= tw
		var chip := Rect2(Vector2(tx, r.position.y + 4.0), Vector2(tw, 14.0))
		cv.draw_rect(chip, UiKit.AMBER if tag == "NEW" else Color(0, 0, 0, 0.7))
		UiKit.text(cv, tag, chip.position + Vector2(4.0, 11.0), 10, Color("#1a1204") if tag == "NEW" else UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiKit.bold())
		tx -= 3.0
	var aim := str(spec.get("aim", ""))
	if aim != "":
		var a := Rect2(Vector2(pic.end.x - 16.0, pic.end.y - 16.0), Vector2(15, 15))
		cv.draw_rect(a, Color(0, 0, 0, 0.6))
		UiKit.icon(cv, "aim_" + aim, a.grow(-1.0))
	var y := pic.end.y + 3.0
	var pairs: Array = fl["at"]
	for p in pairs:
		var s: Dictionary = stats[p[0]]
		var px: float = x + p[1]
		var py: float = y + p[2] * ROW
		UiKit.icon(cv, str(s["icon"]), Rect2(px, py, ICON, ICON))
		UiKit.text(cv, str(s["text"]), Vector2(px + ICON + 2.0, py + 10.0), FONT, UiKit.TEXT)
	y += float(fl["rows"]) * ROW
	_cost_row(cv, spec, x, y, w)


## The foot: the cost's materials as icon and count (red when short), a held part as the cargo icon and "xN", the meta text on the right.
static func _cost_row(cv: CanvasItem, spec: Dictionary, x: float, y: float, w: float) -> void:
	var right := x + w
	var meta := str(spec.get("meta", ""))
	if meta != "":
		var mw := UiKit.text_width(meta, 10)
		UiKit.text(cv, meta, Vector2(right - mw, y + 10.0), 10, UiKit.BAD.lightened(0.2) if spec.get("meta_bad", false) else UiKit.DIM_TEXT)
		right -= mw + 6.0
	var held := int(spec.get("held", -1))
	if held >= 0:
		UiKit.icon(cv, "cargo", Rect2(x, y, ICON, ICON))
		UiKit.text(cv, "x%d" % held, Vector2(x + ICON + 2.0, y + 10.0), FONT, UiKit.TEXT)
		return
	var cost: Dictionary = spec.get("cost", {})
	var short: Dictionary = spec.get("short", {})
	if cost.is_empty():
		return
	var cx := x
	for m in cost:
		var t := str(cost[m])
		var cw := ICON + 1.0 + UiKit.text_width(t, FONT) + 5.0
		if cx + cw - 5.0 > right:
			break
		UiKit.icon(cv, str(m), Rect2(cx, y, ICON, ICON))
		UiKit.text(cv, t, Vector2(cx + ICON + 1.0, y + 10.0), FONT, UiKit.BAD.lightened(0.2) if short.has(m) else UiKit.TEXT)
		cx += cw
