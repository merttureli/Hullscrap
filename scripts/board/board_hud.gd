extends Control
## The HUD of a boarding visit (board_view.gd), in a canvas layer of its own so the dark does not touch it: the site's name and kind at the top and
## "Containers 3/11" under it, the airlock marker (an arrow on the screen edge when the hatch is off screen), the party cards (bottom left, board_cards.gd) with the
## motion tracker above them, the weapon bar (bottom right), what E would do (bottom middle) with the progress ring of a hold, the loot list of an open container,
## what was just taken, a line of words, the loadout screen at the airlock (board_loadout.gd) and, last, the note of whatever icon the mouse is on.
## Draws only; the node above it keeps the state. In the UI colours of docs/ART_STYLE.md.

const Site = preload("res://scripts/board/site.gd")
const Tracker = preload("res://scripts/board/tracker.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Cards = preload("res://scripts/board/board_cards.gd")
const Loadout = preload("res://scripts/board/board_loadout.gd")
const Mods = preload("res://scripts/board/mods.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const PANEL_BG := Color("#1f2630")
const ROW_BG := Color("#2a3340")
const EDGE := Color("#cfd6df")
const EDGE_DIM := Color("#59667a")
const TEXT := Color("#eef2f7")
const DIM_TEXT := Color("#97a3b3")
const GOOD := Color("#6bd34a")
const AMBER := Color("#e1a136")
const CYAN := Color("#43e6ff")
const AIRLOCK := Color("#58e08a")
const BAD := Color("#e0584a")
const TRACKER_R := 62.0
const TRACKER_PAD := 26.0
const EDGE_PAD := 56.0
const PANEL_W := 380.0
const ROW_H := 30.0

var view: Node2D  ## board_view.gd
var _rows: Array = []  # [Rect2] of the loot list rows, in the order of session.entries()
var _shop_rows: Array = []  # [Rect2] of the rows of a person's goods
var _hits: Array = []  # [[Rect2, Dictionary]] what a click on the loadout screen means (drawn fresh every frame)
var _hover: Array = []  # [[Rect2, lines, edge colour]] the icons the mouse can explain (drawn fresh every frame)
var _airlock_box := Rect2()  # where the airlock marker (its label and arrow) was drawn this frame, so the line of words never covers it


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The loadout screen registers what a click on `r` means.
func hit_add(r: Rect2, hit: Dictionary) -> void:
	_hits.append([r, hit])


## The loadout screen and the cards register what the mouse on `r` explains: `lines` (each wrapped), with the edge colour `edge`.
func hover_add(r: Rect2, lines: Array, edge: Color) -> void:
	if not lines.is_empty():
		_hover.append([r, lines, edge])


## What a click at screen point `p` on the loadout screen means: {type: "go" | "pick" | "person" | "slot" | "option", ...}, {} for nothing. The last thing drawn wins.
func loadout_at(p: Vector2) -> Dictionary:
	for i in range(_hits.size() - 1, -1, -1):
		if _hits[i][0].has_point(p):
			return _hits[i][1]
	return {}


## The row of a person's goods under screen point `p`, -1 for none.
func shop_row_at(p: Vector2) -> int:
	for i in _shop_rows.size():
		if _shop_rows[i].has_point(p):
			return i
	return -1


## The row of the loot list under screen point `p`, -1 for none.
func row_at(p: Vector2) -> int:
	for i in _rows.size():
		if _rows[i].has_point(p):
			return i
	return -1


func _draw() -> void:
	if view == null or view.session == null:
		return
	_hits.clear()
	_hover.clear()
	_airlock_box = Rect2()
	var size := get_viewport_rect().size
	_draw_title(size)
	_draw_airlock(size)
	_draw_feeds()
	_draw_tracker(size)
	_draw_cross()
	Cards.draw_weapons(self, size)
	Cards.draw_cards(self, size)
	_draw_feed(size)
	_draw_reveals(size)
	_draw_prompt(size)
	_draw_panel(size)
	_draw_shop(size)
	if view.message_alive():
		_centred(view.message, Vector2(size.x / 2.0, _message_y(view.message, size)), 18, AMBER)
	if view.session.hollow:
		_centred(str(Arms.cfg()["hollow"]["banner"]), Vector2(size.x / 2.0, 118.0), 20, Color("#c9b8ff"))
	if view.picking:
		Loadout.draw(self, size)
	_draw_fade(size)
	_draw_hover(size)


## The height the line of words (the toast: "Airlock sealed.") is drawn at: low in the middle of the screen, and out of the way of the airlock marker when that is there
## (above it when the marker is low on the screen, below it when it is high).
func _message_y(text: String, size: Vector2) -> float:
	var y := size.y - 150.0
	var w := _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var box := Rect2(size.x / 2.0 - w / 2.0 - 12.0, y - 22.0, w + 24.0, 32.0)
	if _airlock_box.size != Vector2.ZERO and box.intersects(_airlock_box.grow(6.0)):
		y = _airlock_box.position.y - 20.0 if _airlock_box.get_center().y > size.y * 0.5 else _airlock_box.end.y + 34.0
	return y


func _font() -> Font:
	return ThemeDB.fallback_font


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(_font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _centred(text: String, at: Vector2, font_size: int, col: Color) -> void:
	var w := _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_rect(Rect2(at + Vector2(-w / 2.0 - 12.0, -font_size - 4.0), Vector2(w + 24.0, font_size + 14.0)), Color(PANEL_BG, 0.85))
	draw_string(_font(), at + Vector2(-w / 2.0, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _draw_title(size: Vector2) -> void:
	var site = view.session.site
	var kind: String = str(Site.config()["kinds"][site.kind]["name"]).to_upper()
	var line := "%s   %s" % [kind, site.site_name]
	var w := _font().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var r := Rect2(Vector2(size.x / 2.0 - w / 2.0 - 16.0, 8.0), Vector2(w + 32.0, 64.0))
	draw_rect(r, Color(PANEL_BG, 0.82))
	draw_rect(r, EDGE_DIM, false, 1.5)
	_text(line, r.position + Vector2(16.0, 26.0), 20, TEXT)
	var count := "Containers %d/%d" % [view.session.opened_count(), view.session.total()]
	var done: bool = view.session.opened_count() >= view.session.total()
	_text(count, r.position + Vector2(16.0, 52.0), 17, GOOD if done else DIM_TEXT)


## The airlock is always marked: a bracket and its name over the hatch, or an arrow on the screen edge pointing to it.
func _draw_airlock(size: Vector2) -> void:
	var site = view.session.site
	var at: Vector2 = view.to_screen(site.hatch_centre())
	var inner := Rect2(Vector2(EDGE_PAD, EDGE_PAD + 60.0), size - Vector2(EDGE_PAD * 2.0, EDGE_PAD * 2.0 + 120.0))
	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 260.0)
	if inner.has_point(at):
		var r := Rect2(at + Vector2(-34.0, -64.0), Vector2(68.0, 22.0))
		draw_rect(r, Color(PANEL_BG, 0.8))
		draw_rect(r, Color(AIRLOCK, pulse), false, 1.5)
		var w := _font().get_string_size("AIRLOCK", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_text("AIRLOCK", r.position + Vector2((r.size.x - w) / 2.0, 16.0), 14, AIRLOCK)
		draw_line(at + Vector2(0.0, -42.0), at + Vector2(0.0, -26.0), Color(AIRLOCK, pulse), 2.0)
		_airlock_box = r.merge(Rect2(at + Vector2(-2.0, -42.0), Vector2(4.0, 16.0)))
		return
	var centre := size / 2.0
	var dir := (at - centre).normalized()
	var k := minf((inner.size.x / 2.0) / maxf(absf(at.x - centre.x), 0.001), (inner.size.y / 2.0) / maxf(absf(at.y - centre.y), 0.001))
	var p := centre + (at - centre) * minf(k, 1.0)
	var tip := p + dir * 16.0
	var side := dir.orthogonal() * 11.0
	draw_colored_polygon(PackedVector2Array([tip, p - dir * 8.0 + side, p - dir * 8.0 - side]), Color(AIRLOCK, pulse))
	var dist: float = view.session.soldier.pos.distance_to(site.hatch_centre())
	var label := "AIRLOCK  %d" % roundi(dist)
	var w2 := _font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var tp := (p - dir * 26.0) - Vector2(w2 / 2.0, -5.0)
	draw_rect(Rect2(tp + Vector2(-6.0, -15.0), Vector2(w2 + 12.0, 22.0)), Color(PANEL_BG, 0.8))
	_text(label, tp, 14, AIRLOCK)
	_airlock_box = Rect2(tp + Vector2(-6.0, -15.0), Vector2(w2 + 12.0, 22.0)).merge(Rect2(p - Vector2(16.0, 16.0), Vector2(32.0, 32.0)))


## The motion tracker: rings every 5 cells of the 25 it reaches, the sweep, and the blips fading behind it.
func _draw_tracker(size: Vector2) -> void:
	var c := Vector2(TRACKER_PAD + TRACKER_R, Cards.top(size, 1 + view.session.party.size()) - 34.0 - TRACKER_R)  # (above the party cards)
	var t: Tracker = view.tracker
	draw_circle(c, TRACKER_R + 6.0, Color(PANEL_BG, 0.85))
	draw_arc(c, TRACKER_R + 6.0, 0.0, TAU, 48, EDGE_DIM, 2.0, true)
	for i in range(1, 4):
		draw_arc(c, TRACKER_R * float(i) / 3.0, 0.0, TAU, 40, Color(AIRLOCK, 0.22), 1.0, true)
	draw_line(c + Vector2(-TRACKER_R, 0.0), c + Vector2(TRACKER_R, 0.0), Color(AIRLOCK, 0.16), 1.0)
	draw_line(c + Vector2(0.0, -TRACKER_R), c + Vector2(0.0, TRACKER_R), Color(AIRLOCK, 0.16), 1.0)
	for k in 10:  # the sweep leaves a fading wedge
		var a: float = t.angle - 0.045 * k
		draw_line(c, c + Vector2.from_angle(a) * TRACKER_R, Color(AIRLOCK, 0.5 * (1.0 - k / 10.0)), 2.0)
	for b in t.blips:
		var f: float = 1.0 - float(b["age"]) / Tracker.BLIP_S
		var bp: Vector2 = c + Vector2.from_angle(float(b["angle"])) * float(b["dist"]) * TRACKER_R
		draw_circle(bp, 3.0 + 3.0 * f, Color(AIRLOCK.lightened(0.4), f))
	draw_circle(c, 2.5, AIRLOCK)
	_text("MOTION", c + Vector2(-22.0, TRACKER_R + 22.0), 12, DIM_TEXT)


func _draw_feed(size: Vector2) -> void:
	var y := size.y - 36.0
	for i in range(view.feed.size() - 1, -1, -1):
		var f: Dictionary = view.feed[i]
		var age: float = view._clock - float(f["t"])
		var a := clampf(1.0 - (age - 3.5) / 1.5, 0.0, 1.0)
		var w := _font().get_string_size(str(f["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_rect(Rect2(size.x - w - 44.0, y - 17.0, w + 28.0, 24.0), Color(PANEL_BG, 0.8 * a))
		_text(str(f["text"]), Vector2(size.x - w - 30.0, y), 16, Color(GOOD, a))
		y -= 28.0


## What E does at the target, and the ring of a hold on the thing being held.
func _draw_prompt(size: Vector2) -> void:
	var t: Dictionary = view.target
	if t.is_empty() or view.panel >= 0 or view.shop >= 0:
		return
	var s = view.session
	var site = s.site
	var text := ""
	var need := 0.0
	var at := Vector2.ZERO
	match str(t["type"]):
		"airlock":
			text = "E: leave through the airlock"
			var down: Array = s.downed_party()
			if view._leave_t > 0.0 and not down.is_empty():
				text = "E: leave %s behind (lost for good%s)     Esc: stay" % [", ".join(down), view.lost_note(down)]
			at = view.to_screen(site.hatch_centre())
		"container":
			var p: Dictionary = site.props[t["id"]]
			var name: String = str(Site.config()["props"][p["prop"]]["name"])
			at = view.to_screen(site.centre_of(p))
			if s.opened.has(t["id"]):
				text = "E: look in the %s again" % name.to_lower()
			else:
				need = float(Site.config()["props"][p["prop"]]["hold"])
				text = "Hold E: open the %s" % name.to_lower()
		"npc":
			var person: Dictionary = s.people.find(t["id"])
			at = view.to_screen(person["m"].pos)
			text = "E: talk to %s" % person["name"] if not person["shop_open"] else "E: trade with %s" % person["name"]
			if person["done"] and not person["shop_open"]:
				text = "%s has said what there is to say" % person["name"]
		"revive":
			var who = s.party[t["id"]]["m"]
			at = view.to_screen(who.pos)
			need = float(Arms.cfg()["revive_s"])
			text = "Hold E: bring %s round (%d s)" % [who.name, int(need)]
		"sentry":
			at = view.to_screen(s.foes.find(t["id"])["m"].pos)
			need = float(Arms.cfg()["hack_sentry_s"])
			text = "Hold E: hack the sentry (%d s)" % int(need)
		"door":
			var d: Dictionary = site.doors[t["id"]]
			at = view.to_screen(site.door_centre(d))
			if d["lock"] == "hack":
				need = float(Site.config()["hack_s"])
				text = "Hold E: hack the lock (%d s)" % int(need)
			else:
				text = "E: use the %s keycard" % str(d["card"]) if s.keys.has(d["card"]) else "Locked: it wants the %s keycard" % str(d["card"])
	_centred(text, Vector2(size.x / 2.0, size.y - 96.0), 18, TEXT)
	if need > 0.0 and view.hold > 0.0:
		var f := clampf(view.hold / need, 0.0, 1.0)
		draw_arc(at, 24.0, 0.0, TAU, 40, Color(0, 0, 0, 0.6), 7.0, true)
		draw_arc(at, 24.0, -PI / 2.0, -PI / 2.0 + TAU * f, 40, AMBER if str(t["type"]) == "door" else CYAN, 5.0, true)


## What someone's word marked: a pulsing diamond over the container (or the locked door) with its name, held at the edge of the screen when it is off it.
func _draw_reveals(size: Vector2) -> void:
	var s = view.session
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 240.0)
	var spots := []
	for id in s.people.revealed:
		if not s.opened.has(id):
			spots.append([s.site.centre_of(s.site.props[id]), str(Site.config()["props"][s.site.props[id]["prop"]]["name"])])
	for id in s.people.revealed_doors:
		if not s.unlocked.has(id):
			spots.append([s.site.door_centre(s.site.doors[id]), "Locked door"])
	var inner := Rect2(Vector2(40.0, 100.0), size - Vector2(80.0, 360.0))  # (clear of the tracker, the arms and the lines of what was taken)
	for i in spots.size():
		var sp: Array = spots[i]
		var at: Vector2 = view.to_screen(sp[0])
		if not inner.has_point(at):
			at = Vector2(clampf(at.x, inner.position.x, inner.end.x), clampf(at.y, inner.position.y, inner.end.y))
		var col := Color(AMBER, pulse)
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -12), at + Vector2(10, 0), at + Vector2(0, 12), at + Vector2(-10, 0)]), Color(col, 0.35))
		draw_polyline(PackedVector2Array([at + Vector2(0, -12), at + Vector2(10, 0), at + Vector2(0, 12), at + Vector2(-10, 0), at + Vector2(0, -12)]), col, 2.0)
		var label := str(sp[1])
		var w := _font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_text(label, Vector2(clampf(at.x - w / 2.0, 8.0, size.x - w - 8.0), at.y - 18.0 - 15.0 * float(i % 3)), 13, col)  # (staggered, so two near each other can be read)


## A person's goods: three rows with a price, 1-3 buys.
func _draw_shop(size: Vector2) -> void:
	_shop_rows.clear()
	if view.shop < 0:
		return
	var s = view.session
	var person: Dictionary = s.people.find(view.shop)
	if person.is_empty():
		return
	var rows: Array = person["shop"]
	var h := 54.0 + ROW_H * rows.size() + 34.0
	var r := Rect2(Vector2(size.x / 2.0 - PANEL_W / 2.0 - 20.0, size.y - 120.0 - h), Vector2(PANEL_W + 40.0, h))
	draw_rect(r, Color(PANEL_BG, 0.94))
	draw_rect(r, EDGE, false, 2.0)
	_text("%s, selling" % person["name"], r.position + Vector2(16.0, 30.0), 20, TEXT)
	var credits: int = s.ship.inventory.count("credits") if s.ship != null else 0
	var cw := _font().get_string_size("%d credits" % credits, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_text("%d credits" % credits, r.position + Vector2(r.size.x - cw - 16.0, 30.0), 15, AMBER)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var rr := Rect2(r.position + Vector2(10.0, 44.0 + ROW_H * i), Vector2(r.size.x - 20.0, ROW_H - 4.0))
		_shop_rows.append(rr)
		var sold: bool = bool(row["sold"])
		var afford: bool = credits >= int(row["price"])
		draw_rect(rr, ROW_BG if not sold else Color(ROW_BG, 0.4))
		_text("%d" % (i + 1), rr.position + Vector2(8.0, 20.0), 15, DIM_TEXT)
		_text("%s x%d" % [s._name(str(row["item"])), int(row["n"])], rr.position + Vector2(30.0, 20.0), 17, TEXT if not sold else DIM_TEXT)
		var price := "sold" if sold else "%d cr" % int(row["price"])
		var pw := _font().get_string_size(price, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_text(price, rr.position + Vector2(rr.size.x - pw - 10.0, 20.0), 16, DIM_TEXT if sold else (GOOD if afford else BAD))
	_text("1-%d: buy     Esc: close" % rows.size(), r.position + Vector2(16.0, h - 12.0), 14, DIM_TEXT)


## The loot list of an open container.
func _draw_panel(size: Vector2) -> void:
	_rows.clear()
	if view.panel < 0:
		return
	var s = view.session
	var entries: Array = s.entries(view.panel)
	var p: Dictionary = s.site.props[view.panel]
	var h := 54.0 + ROW_H * entries.size() + 34.0
	var r := Rect2(Vector2(size.x / 2.0 - PANEL_W / 2.0, size.y - 120.0 - h), Vector2(PANEL_W, h))
	draw_rect(r, Color(PANEL_BG, 0.94))
	draw_rect(r, EDGE, false, 2.0)
	_text(str(Site.config()["props"][p["prop"]]["name"]), r.position + Vector2(16.0, 30.0), 20, TEXT)
	for i in entries.size():
		var rr := Rect2(r.position + Vector2(10.0, 44.0 + ROW_H * i), Vector2(PANEL_W - 20.0, ROW_H - 4.0))
		_rows.append(rr)
		draw_rect(rr, ROW_BG)
		var text: String = str(entries[i]["text"])
		var col := CYAN if text.begins_with("Blueprint") else (AMBER if text.contains("keycard") or text.begins_with("Log") else TEXT)
		_text("%d" % (i + 1), rr.position + Vector2(8.0, 20.0), 15, DIM_TEXT)
		_text(text, rr.position + Vector2(30.0, 20.0), 17, col)
		if entries[i].has("bonus"):  # the Salvage Rig's share, in the mod's colour
			var tw := _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			_text(str(entries[i]["bonus"]), rr.position + Vector2(30.0 + tw + 10.0, 20.0), 15, entries[i]["color"])
	var pick := "1: take it" if entries.size() == 1 else "1-%d: take one" % entries.size()
	_text("E: take all     %s     Esc: close" % pick, r.position + Vector2(16.0, h - 12.0), 14, DIM_TEXT)


## After the soldier goes down the screen fades out, with where he wakes.
func _draw_fade(size: Vector2) -> void:
	if not view.session.downed:
		return
	var f := clampf(view._down_t / (view.DOWN_S * 0.7), 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, f))
	if f >= 0.6:
		_centred(str(Arms.cfg()["down_text"]), size / 2.0, 24, TEXT)


## The crosshair at the aim.
func _draw_cross() -> void:
	var at: Vector2 = view.aim_screen()
	draw_arc(at, 9.0, 0.0, TAU, 20, Color(TEXT, 0.7), 1.5, true)
	draw_circle(at, 1.5, Color(TEXT, 0.9))


## The Spotter Cam's rooms read as a camera feed: corner brackets and a label, in the mod's colour.
func _draw_feeds() -> void:
	var col := Mods.color("spotter_cam")
	for rid in view._cam_lights:
		var e := float(view._cam_energy.get(rid, 0.0))
		if e < 0.05:
			continue
		var rect: Rect2i = view.session.site.rooms[rid]["rect"]
		var a: Vector2 = view.to_screen(Vector2(rect.position) - Vector2(0.4, 0.4))
		var b: Vector2 = view.to_screen(Vector2(rect.end) + Vector2(0.4, 0.4))
		var c := Color(col, minf(e * 1.6, 0.8))
		var k := 14.0
		for corner in [[a, Vector2(1, 1)], [Vector2(b.x, a.y), Vector2(-1, 1)], [Vector2(a.x, b.y), Vector2(1, -1)], [b, Vector2(-1, -1)]]:
			draw_line(corner[0], corner[0] + Vector2(k * corner[1].x, 0), c, 2.0)
			draw_line(corner[0], corner[0] + Vector2(0, k * corner[1].y), c, 2.0)
		_text("CAM", a + Vector2(6, 16), 11, c)


## The note of the icon the mouse is on: its lines, wrapped, on a panel edged in the icon's colour.
func _draw_hover(size: Vector2) -> void:
	var mouse := get_local_mouse_position()
	for i in range(_hover.size() - 1, -1, -1):
		var h: Array = _hover[i]
		if not h[0].has_point(mouse):
			continue
		var lines := PackedStringArray()
		for t in h[1]:
			lines.append_array(UiKit.wrap(str(t), 300.0, 12))
		var w := 16.0
		for l in lines:
			w = maxf(w, UiKit.text_width(l, 12) + 16.0)
		var ht := float(lines.size()) * 16.0 + 12.0
		var at := Vector2(clampf(h[0].position.x, 4.0, size.x - w - 4.0), h[0].position.y - ht - 6.0)
		if at.y < 4.0:
			at.y = h[0].end.y + 6.0
		UiKit.note(self, lines, at, h[2])
		return
