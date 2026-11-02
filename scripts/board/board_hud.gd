extends Control
## The HUD of a boarding visit (board_view.gd), in a canvas layer of its own so the dark does not touch it: the site's name and kind at the top and
## "Containers 3/11" under it, the airlock marker (an arrow on the screen edge when the hatch is off screen), the motion tracker (bottom left), what
## E would do (bottom middle) with the progress ring of a hold, the loot list of an open container, what was just taken, and a line of words.
## Draws only; the node above it keeps the state. In the UI colours of docs/ART_STYLE.md.

const Site = preload("res://scripts/board/site.gd")
const Tracker = preload("res://scripts/board/tracker.gd")
const Arms = preload("res://scripts/board/arms.gd")

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
var _pick_rows: Array = []  # [Rect2] of the crew picker rows
var _go := Rect2()  # the picker's "go aboard" button
var _shop_rows: Array = []  # [Rect2] of the rows of a person's goods


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The row of the crew picker under screen point `p`, -2 for the go button, -1 for none.
func pick_at(p: Vector2) -> int:
	if _go.has_point(p):
		return -2
	for i in _pick_rows.size():
		if _pick_rows[i].has_point(p):
			return i
	return -1


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
	var size := get_viewport_rect().size
	_draw_title(size)
	_draw_airlock(size)
	_draw_tracker(size)
	_draw_tracers()
	_draw_arms(size)
	_draw_party(size)
	_draw_feed(size)
	_draw_reveals(size)
	_draw_prompt(size)
	_draw_panel(size)
	_draw_shop(size)
	if view.message_alive():
		_centred(view.message, Vector2(size.x / 2.0, size.y - 150.0), 18, AMBER)
	if view.session.hollow:
		_centred(str(Arms.cfg()["hollow"]["banner"]), Vector2(size.x / 2.0, 118.0), 20, Color("#c9b8ff"))
	_draw_picker(size)
	_draw_fade(size)


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


## The motion tracker: rings every 5 cells of the 25 it reaches, the sweep, and the blips fading behind it.
func _draw_tracker(size: Vector2) -> void:
	var c := Vector2(TRACKER_PAD + TRACKER_R, size.y - TRACKER_PAD - TRACKER_R)
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
				text = "E: leave %s behind (lost for good)     Esc: stay" % ", ".join(down)
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
	var pick := "1: take it" if entries.size() == 1 else "1-%d: take one" % entries.size()
	_text("E: take all     %s     Esc: close" % pick, r.position + Vector2(16.0, h - 12.0), 14, DIM_TEXT)


## The lines the shots drew: his in a warm white, a foe's in red.
func _draw_tracers() -> void:
	var life := float(Arms.cfg()["tracer_s"])
	for t in view.tracers:
		var a := clampf(1.0 - float(t["t"]) / life, 0.0, 1.0)
		var col := Color(1.0, 0.45, 0.35, a) if t["foe"] else Color(1.0, 0.95, 0.7, a)
		draw_line(view.to_screen(t["from"]), view.to_screen(t["to"]), col, 2.0)


## His health and weapon (bottom right, over what was taken): "HP 80", the weapon, rounds in it / in the hold, and the other weapon he carries.
func _draw_arms(size: Vector2) -> void:
	var s = view.session
	var m = s.soldier
	var g: Dictionary = s.gun()
	var x := size.x - 300.0
	var y := size.y - 24.0 - 28.0 * float(view.feed.size())
	var hp_f := clampf(m.hp / maxf(m.max_hp, 1.0), 0.0, 1.0)
	draw_rect(Rect2(x, y - 74.0, 276.0, 70.0), Color(PANEL_BG, 0.85))
	draw_rect(Rect2(x, y - 74.0, 276.0, 70.0), EDGE_DIM, false, 1.5)
	draw_rect(Rect2(x + 12.0, y - 64.0, 252.0, 8.0), ROW_BG)
	draw_rect(Rect2(x + 12.0, y - 64.0, 252.0 * hp_f, 8.0), GOOD if hp_f > 0.5 else (AMBER if hp_f > 0.25 else BAD))
	_text(str(g["w"]["name"]), Vector2(x + 12.0, y - 36.0), 16, TEXT)
	var ammo := ""
	if Arms.has_mag(g):
		ammo = "%d / %d" % [int(g["mag"]), s.reserve()]
		if float(g["reload"]) > 0.0:
			ammo = "reloading"
	else:
		ammo = "melee"
	var col := TEXT if Arms.has_mag(g) and int(g["mag"]) > 0 else (BAD if Arms.has_mag(g) else DIM_TEXT)
	var w := _font().get_string_size(ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_text(ammo, Vector2(x + 264.0 - w, y - 34.0), 20, col)
	if s.guns.size() > 1:
		_text("Q: %s" % str(s.guns[1 - s.cur]["w"]["name"]), Vector2(x + 12.0, y - 14.0), 13, DIM_TEXT)
	_text("R reload   F light", Vector2(x + 150.0, y - 14.0), 13, DIM_TEXT)
	var at: Vector2 = view.aim_screen()
	draw_arc(at, 9.0, 0.0, TAU, 20, Color(TEXT, 0.7), 1.5, true)
	draw_circle(at, 1.5, Color(TEXT, 0.9))


## The crew who came along (top left): name and a small health bar; a downed one is marked in red, and in the world by a cross.
func _draw_party(size: Vector2) -> void:
	var y := 84.0
	for p in view.session.party:
		var m = p["m"]
		var f := clampf(m.hp / maxf(m.max_hp, 1.0), 0.0, 1.0)
		draw_rect(Rect2(16.0, y, 168.0, 34.0), Color(PANEL_BG, 0.82))
		draw_rect(Rect2(16.0, y, 168.0, 34.0), EDGE_DIM if not m.is_down() else BAD, false, 1.5)
		_text(str(m.name), Vector2(26.0, y + 16.0), 15, TEXT)
		draw_rect(Rect2(26.0, y + 23.0, 148.0, 5.0), ROW_BG)
		draw_rect(Rect2(26.0, y + 23.0, 148.0 * f, 5.0), GOOD if f > 0.5 else (AMBER if f > 0.25 else BAD))
		if m.is_down():
			_text("DOWN", Vector2(130.0, y + 16.0), 13, BAD)
			var at: Vector2 = view.to_screen(m.pos)
			if Rect2(Vector2.ZERO, size).has_point(at):
				draw_line(at + Vector2(-9.0, -9.0), at + Vector2(9.0, 9.0), BAD, 3.0)
				draw_line(at + Vector2(9.0, -9.0), at + Vector2(-9.0, 9.0), BAD, 3.0)
		y += 40.0


## Before going aboard: which crew come along.
func _draw_picker(size: Vector2) -> void:
	_pick_rows.clear()
	_go = Rect2()
	if not view.picking:
		return
	var rows: Array = view.pick_rows()
	var cap := int(Arms.cfg()["party_max"])
	var w := 460.0
	var h := 96.0 + ROW_H * rows.size() + 44.0
	var r := Rect2(Vector2(size.x / 2.0 - w / 2.0, size.y / 2.0 - h / 2.0), Vector2(w, h))
	draw_rect(r, Color(PANEL_BG, 0.96))
	draw_rect(r, EDGE, false, 2.0)
	_text("Take crew along?", r.position + Vector2(18.0, 32.0), 22, TEXT)
	_text("Up to %d. Crew who are down when you leave are lost." % cap, r.position + Vector2(18.0, 56.0), 14, DIM_TEXT)
	for i in rows.size():
		var rr := Rect2(r.position + Vector2(12.0, 70.0 + ROW_H * i), Vector2(w - 24.0, ROW_H - 4.0))
		_pick_rows.append(rr)
		var on: bool = view.pick.has(rows[i]["name"])
		draw_rect(rr, ROW_BG if not on else Color(GOOD, 0.3))
		if on:
			draw_rect(rr, GOOD, false, 1.5)
		_text("%d" % (i + 1), rr.position + Vector2(8.0, 20.0), 15, DIM_TEXT)
		_text("%s   %s" % [rows[i]["name"], str(rows[i]["species"]).capitalize()], rr.position + Vector2(30.0, 20.0), 17, TEXT)
		_text("%d/%d" % [roundi(rows[i]["hp"]), roundi(rows[i]["max_hp"])], rr.position + Vector2(w - 90.0, 20.0), 15, DIM_TEXT)
	_go = Rect2(r.position + Vector2(w - 150.0, h - 42.0), Vector2(132.0, 30.0))
	draw_rect(_go, Color(AIRLOCK, 0.35))
	draw_rect(_go, AIRLOCK, false, 1.5)
	_text("Go aboard", _go.position + Vector2(20.0, 21.0), 17, TEXT)
	_text("1-9: pick     Enter: go     Esc: alone", r.position + Vector2(18.0, h - 22.0), 13, DIM_TEXT)


## After the soldier goes down the screen fades out, with where he wakes.
func _draw_fade(size: Vector2) -> void:
	if not view.session.downed:
		return
	var f := clampf(view._down_t / (view.DOWN_S * 0.7), 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, f))
	if f >= 0.6:
		_centred(str(Arms.cfg()["down_text"]), size / 2.0, 24, TEXT)
