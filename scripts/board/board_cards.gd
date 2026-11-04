extends RefCounted
## The fight HUD of a boarding visit (docs/BOARDING.md, B4), drawn on the HUD (board_hud.gd) with static functions:
## - the party cards, bottom left, the soldier first and then whoever came along: the head, the name, the hp bar with its number, the weapon, and small icons for the
##   body gear and the mods worn. A person who is down says "DOWN, hold E" with the revive progress.
## - the weapon bar, bottom right: the soldier's two slots with the item art and the name. The active one is lit and shows the magazine and the reserve; a reload is a
##   progress ring; the Q hint.
## Each icon has a hover line (the HUD's hover list, drawn last as a note). In the UI colours of docs/ART_STYLE.md.

const Arms = preload("res://scripts/board/arms.gd")
const Art = preload("res://scripts/view/art.gd")
const Kit = preload("res://scripts/board/kit.gd")
const Mods = preload("res://scripts/board/mods.gd")
const Air = preload("res://scripts/board/air.gd")
const ShipView = preload("res://scripts/view/ship_view.gd")

const W := 268.0
const H := 68.0
const GAP := 6.0
const PAD := 16.0
const BOTTOM := 14.0
const BODY_COLORS := {"basic_armor": "#8aa0bd", "eva_suit": "#dfe8f2", "exosuit": "#e6893a", "salamander_suit": "#e0553a", "heat_suit": "#e8c040"}

static var _tex := {}  # art name -> Texture2D or null
static var _crops := {}  # head frame -> the rectangle of it that is drawn


## The top of the first card for a party of `n` people.
static func top(size: Vector2, n: int) -> float:
	return size.y - BOTTOM - float(n) * (H + GAP) + GAP


# --- the cards ---------------------------------------------------------------------------------------------------------

static func draw_cards(h, size: Vector2) -> void:
	var s = h.view.session
	var who := [{"m": s.soldier, "p": null}]
	for p in s.party:
		who.append({"m": p["m"], "p": p})
	var y0 := top(size, who.size())
	for i in who.size():
		_card(h, Rect2(PAD, y0 + float(i) * (H + GAP), W, H), who[i], i)


static func _card(h, r: Rect2, e: Dictionary, index: int) -> void:
	var s = h.view.session
	var m = e["m"]
	var down: bool = m.is_down()
	h.draw_rect(r, Color(h.PANEL_BG, 0.86))
	h.draw_rect(r, h.BAD if down else (h.EDGE if index == 0 else h.EDGE_DIM), false, 1.5)
	_portrait(h, Rect2(r.position + Vector2(8, 9), Vector2(50, 50)), m)
	var x := r.position.x + 66.0
	h._text(str(m.name), Vector2(x, r.position.y + 22.0), 15, h.TEXT if not down else h.DIM_TEXT)
	var bar := Rect2(x, r.position.y + 28.0, r.size.x - 76.0, 7.0)
	var f := clampf(m.hp / maxf(m.max_hp, 1.0), 0.0, 1.0)
	h.draw_rect(bar, h.ROW_BG)
	if down:
		var rev := _revive(h, e)
		h.draw_rect(Rect2(bar.position, Vector2(bar.size.x * rev, bar.size.y)), h.CYAN)
		var t := "DOWN, hold E" if index > 0 else "DOWN"
		var w: float = h._font().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		h._text(t, Vector2(r.end.x - w - 10.0, r.position.y + 22.0), 13, h.BAD)
	else:
		h.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), h.GOOD if f > 0.5 else (h.AMBER if f > 0.25 else h.BAD))
		var n := "%d/%d" % [ceili(m.hp), roundi(m.max_hp)]
		var w2: float = h._font().get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		h._text(n, Vector2(r.end.x - w2 - 10.0, r.position.y + 22.0), 13, h.DIM_TEXT)
	_air(h, r, m)
	# the gear: the weapon, the body, the mods
	var art: String = str(s.gun()["w"]["art"]) if e["p"] == null else str(e["p"]["gun"]["w"]["art"])
	var wid: String = str(s.gun()["id"]) if e["p"] == null else str(e["p"]["gun"]["id"])
	var wr := Rect2(x, r.position.y + 40.0, 46.0, 22.0)
	h.draw_rect(wr, Color(h.ROW_BG, 0.8))
	_art(h, art, wr.grow(-2.0), 0.45 if down else 1.0)
	h.hover_add(wr, _weapon_lines(wid), h.EDGE)
	var kit: Dictionary = Kit.of(m)
	var gx := x + 54.0
	var br := Rect2(gx, r.position.y + 40.0, 22.0, 22.0)
	_body_icon(h, br, str(kit["body"]))
	h.hover_add(br, ["Body gear", Kit.body_line(str(kit["body"]))] if str(kit["body"]) != "" else ["No body gear."], h.EDGE_DIM)
	for k in kit["mods"].size():
		var mr := Rect2(gx + 28.0 * float(k + 1), r.position.y + 40.0, 22.0, 22.0)
		var item := str(kit["mods"][k])
		if item == "":
			h.draw_rect(mr, Color(h.ROW_BG, 0.5), false, 1.0)
			continue
		Mods.draw_icon(h, item, mr, down)
		h.hover_add(mr, Mods.hover(item), Mods.color(Mods.parse(item)["mod"]))


## The AIR line: OK, THIN or NONE where the person stands, the seconds they have left in that air (or "suit" when a seal keeps them safe).
static func _air(h, r: Rect2, m) -> void:
	var a: Dictionary = Air.line(h.view.session.site, m, m.pos)
	var t := "AIR " + str(a["word"])
	var col: Color = h.GOOD
	if str(a["word"]) != "OK":
		col = h.AMBER if str(a["word"]) == "THIN" else h.BAD
		t += " suit" if bool(a["sealed"]) else (" %ds" % ceili(float(a["secs"])) if float(a["secs"]) >= 0.0 else "")
	var w: float = h._font().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	h._text(t, Vector2(r.end.x - w - 8.0, r.position.y + 58.0), 12, col)


## How far the revive of this person has got (0 to 1): the soldier's hold of E on them, or a crew mate kneeling by them.
static func _revive(h, e: Dictionary) -> float:
	var s = h.view.session
	var need := float(Arms.cfg()["revive_s"])
	var best := 0.0
	var m = e["m"]
	var t: Dictionary = h.view.target
	if e["p"] != null and str(t.get("type", "")) == "revive" and s.party[int(t["id"])] == e["p"]:
		best = h.view.hold / need
	for q in s.party:
		if q != e["p"] and float(q["revive"]) > 0.0 and q["m"].pos.distance_to(m.pos) <= 2.4:
			best = maxf(best, float(q["revive"]) / need)
	return clampf(best, 0.0, 1.0)


static func _weapon_lines(id: String) -> Array:
	var w := Arms.weapon(id)
	if w.is_empty():
		return ["No weapon."]
	var line := "%s, %s damage" % [str(w["class"]).capitalize(), roundi(float(w["damage"]))]
	if bool(w["melee"]):
		line += ", a swing every %.1f s" % (1.0 / float(w["rate"]))
	else:
		line += ", %d rounds, %.1f shots a second" % [int(w["mag"]), float(w["rate"])]
	return [str(w["name"]), line]


# --- the weapon bar ----------------------------------------------------------------------------------------------------

static func draw_weapons(h, size: Vector2) -> void:
	var s = h.view.session
	var sw := 160.0
	var sh := 72.0
	var x0 := size.x - 24.0 - 2.0 * sw - 8.0
	var y0 := size.y - 18.0 - 28.0 * float(h.view.feed.size()) - sh
	for i in 2:
		var r := Rect2(x0 + float(i) * (sw + 8.0), y0, sw, sh)
		if i >= s.guns.size():
			h.draw_rect(r, Color(h.PANEL_BG, 0.5))
			h.draw_rect(r, h.EDGE_DIM, false, 1.0)
			h._text("empty", r.position + Vector2(12, 28), 14, h.DIM_TEXT)
			continue
		_slot(h, r, s.guns[i], i == s.cur, s)
	var hint := "Q swap    R reload    F light"
	var hw: float = h._font().get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	h._text(hint, Vector2(size.x - 24.0 - hw, y0 - 8.0), 12, h.DIM_TEXT)


static func _slot(h, r: Rect2, g: Dictionary, active: bool, s) -> void:
	var w: Dictionary = g["w"]
	h.draw_rect(r, Color(h.PANEL_BG, 0.9 if active else 0.62))
	if active:
		h.draw_rect(r, Color(h.AMBER, 0.12))
	h.draw_rect(r, h.AMBER if active else h.EDGE_DIM, false, 2.0 if active else 1.0)
	var ir := Rect2(r.position + Vector2(8, 8), Vector2(60, 30))
	h.draw_rect(ir, Color(h.ROW_BG, 0.8))
	_art(h, str(w["art"]), ir.grow(-3.0), 1.0 if active else 0.55)
	h.hover_add(r, _weapon_lines(str(g["id"])), h.AMBER if active else h.EDGE_DIM)
	h._text(str(w["name"]), r.position + Vector2(8, 54), 13, h.TEXT if active else h.DIM_TEXT)
	var centre := Vector2(r.end.x - 30.0, r.position.y + 26.0)
	if Arms.has_mag(g):
		var mag := int(g["mag"])
		var maxm := float(w["mag"])
		h.draw_arc(centre, 17.0, 0.0, TAU, 28, Color(0, 0, 0, 0.5), 5.0, true)
		if float(g["reload"]) > 0.0:  # a reload: the ring fills as the new magazine goes in
			var p := 1.0 - float(g["reload"]) / maxf(float(w["reload_s"]), 0.01)
			h.draw_arc(centre, 17.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(p, 0.0, 1.0), 28, h.CYAN, 4.0, true)
			if active:
				h._text("...", centre + Vector2(-8, 5), 14, h.CYAN)
		else:
			h.draw_arc(centre, 17.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(float(mag) / maxm, 0.0, 1.0), 28, h.TEXT if mag > 0 else h.BAD, 3.0, true)
			var t := str(mag)
			var tw: float = h._font().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			h._text(t, centre + Vector2(-tw / 2.0, 6), 16, h.TEXT if mag > 0 else h.BAD)
		if active:
			var res := "%d in the hold" % s.reserve()
			h._text(res, r.position + Vector2(r.size.x - 8.0 - h._font().get_string_size(res, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 66), 12, h.DIM_TEXT if s.reserve() > 0 else h.BAD)
	else:
		h._text("melee", centre + Vector2(-26, 5), 14, h.DIM_TEXT)
	if not active:
		h._text("Q", r.position + Vector2(r.size.x - 18.0, 66), 13, h.AMBER)


# --- small drawing --------------------------------------------------------------------------------------------------------

## The art of item `art` (art/items/<art>.png) fitted into `r`; a plain bar when there is none.
static func _art(h, art: String, r: Rect2, alpha: float) -> void:
	if not _tex.has(art):
		var path := "res://art/items/%s.png" % art
		_tex[art] = load(path) if ResourceLoader.exists(path) else null
	var t: Texture2D = _tex[art]
	if t == null:
		h.draw_rect(r.grow(-4.0), Color(h.TEXT, alpha * 0.5))
		return
	var k := minf(r.size.x / t.get_width(), r.size.y / t.get_height())
	var sz := Vector2(t.get_width(), t.get_height()) * k
	h.draw_texture_rect(t, Rect2(r.get_center() - sz / 2.0, sz), false, Color(1, 1, 1, alpha))


## A body gear icon: a vest in the gear's colour, a dim empty frame when nothing is worn.
static func _body_icon(h, r: Rect2, item: String) -> void:
	if item == "":
		h.draw_rect(r, Color(h.ROW_BG, 0.5), false, 1.0)
		return
	var col := Color(str(BODY_COLORS.get(item, "#aaaaaa")))
	var u := r.size.x / 16.0
	var o := r.position
	h.draw_rect(r, Color(col.darkened(0.75), 1.0))
	h.draw_rect(r, col, false, 1.0)
	var pts := PackedVector2Array([o + Vector2(3, 3) * u, o + Vector2(6, 2.5) * u, o + Vector2(8, 4) * u, o + Vector2(10, 2.5) * u, o + Vector2(13, 3) * u, o + Vector2(12.5, 8) * u, o + Vector2(11, 8) * u, o + Vector2(11, 13) * u, o + Vector2(5, 13) * u, o + Vector2(5, 8) * u, o + Vector2(3.5, 8) * u])
	h.draw_colored_polygon(pts, col)
	h.draw_line(o + Vector2(8, 4.5) * u, o + Vector2(8, 12.5) * u, col.darkened(0.5), maxf(1.0, u * 0.9))


## The head of person `m` in their outfit colour, fitted into `box`; a disc with the initial when the art has no head.
static func _portrait(h, box: Rect2, m) -> void:
	h.draw_rect(box, Color(0.09, 0.12, 0.17))
	var sheet = Art.crew(Art.crew_rig(m.rig()))
	var head = sheet.layers.get("head") if sheet != null else null
	var look: Dictionary = m.look if not m.look.is_empty() else ShipView.LOOKS.get(m.name, ShipView.OTHER_LOOK)
	var suit := Color(look.get("suit", "#33c6d6"))
	if head == null:
		h.draw_circle(box.get_center(), box.size.x * 0.36, suit)
		return
	var frame: int = head.named_frames.get(m.head, head.named_frames.get("hair", 0))
	var key := "%d:%d" % [head.get_instance_id(), frame]
	if not _crops.has(key):
		var used := Rect2i(Vector2i.ZERO, Vector2i(head.frame))
		if head.image != null:
			var u: Rect2i = head.image.get_region(Rect2i(head.region(frame))).get_used_rect()
			if u.size.x > 0 and u.size.y > 0:
				used = u
		_crops[key] = Rect2(used)
	var crop: Rect2 = _crops[key]
	var k := maxf(floorf(minf((box.size.x - 4.0) / crop.size.x, (box.size.y - 4.0) / crop.size.y)), 1.0)
	var dest := Rect2(box.get_center() - crop.size * k / 2.0, crop.size * k)
	h.draw_texture_rect_region(head.tinted(suit), dest, Rect2(head.region(frame).position + crop.position, crop.size), Color(0.5, 0.5, 0.55) if m.is_down() else Color.WHITE)
