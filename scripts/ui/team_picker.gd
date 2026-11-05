extends Control
## The away-team picker: who goes down to a site (E near an expedition site, docs/CONTENT.md section 17). One card per crew member who may go (the soldier and the
## any crew, posted or not: expedition.gd candidates) with their species, health, what they carry and whether a sealed suit protects them; keys 1-9 or a click pick up to
## data/expeditions.json team.max, Enter sends the team (one is enough: you may go alone), Esc stays aboard. Only draws and reads input; the rules are expedition.gd.

## Emitted with the names picked when the team is sent.
signal chosen(names: Array)
## Emitted when the player stays aboard.
signal cancelled

const Expedition = preload("res://scripts/space/expedition.gd")
const Kit = preload("res://scripts/board/kit.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Air = preload("res://scripts/board/air.gd")

const WIDTH := 940.0
const PAD := 26.0
const ROW_H := 62.0
const PANEL_BG := Color("#1f2630")
const ROW_BG := Color("#2a3340")
const EDGE := Color("#cfd6df")
const EDGE_DIM := Color("#59667a")
const TEXT := Color("#eef2f7")
const DIM_TEXT := Color("#97a3b3")
const AMBER := Color("#e1a136")
const CYAN := Color("#43e6ff")
const GOOD := Color("#6bd34a")
const BAD := Color("#e0413b")

var map: Control  ## the MapView: its campaign and ship
var poi := {}  ## the site
var pick: Array = []  ## names picked, in the order picked
var message := ""
var hover := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


## Show the picker for site `p_poi`.
func open(p_poi: Dictionary) -> void:
	poi = p_poi
	pick = []
	message = ""
	hover = -1
	visible = true


func close() -> void:
	visible = false


func ship():
	return map.ship()


## The crew who may go, as cards: [{name, species, hp, max_hp, gear, sealed, soldier}].
func rows() -> Array:
	var sh = ship()
	return Expedition.candidates(sh).map(func(m): return {"name": m.name, "species": m.species, "hp": m.hp, "max_hp": m.max_hp, "gear": gear_text(sh, m), "sealed": Air.sealed(m), "soldier": m.is_player})


## What a member carries, in words: weapons and body gear and mods ("Service Pistol, Carbine, Exosuit"), the sidearm alone when that is all.
static func gear_text(sh, m) -> String:
	var names := []
	for w in Kit.weapons_of(m):
		names.append(str(Arms.weapon(str(w)).get("name", w)))
	if not m.kit.is_empty():
		var k := Kit.of(m)
		if str(k["body"]) != "":
			names.append(sh.crafting.name_of(str(k["body"]), sh.components))
		for item in k["mods"]:
			if str(item) != "":
				names.append(load("res://scripts/board/mods.gd").label(str(item)))
	return ", ".join(names)


## Pick or drop the `i`th card (at most team.max).
func toggle(i: int) -> void:
	var r := rows()
	if i < 0 or i >= r.size():
		return
	var n: String = r[i]["name"]
	message = ""
	if pick.has(n):
		pick.erase(n)
	elif pick.size() < Expedition.team_max():
		pick.append(n)
	else:
		message = "At most %d can go." % Expedition.team_max()


## Send the team picked. Returns why not ("" when sent).
func confirm() -> String:
	var why := Expedition.check_team(ship(), pick)
	if why != "":
		message = why
		return why
	var names := pick.duplicate()
	close()
	chosen.emit(names)
	return ""


func cancel() -> void:
	close()
	cancelled.emit()


func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey):
		return
	get_viewport().set_input_as_handled()
	if not e.pressed or e.echo:
		return
	if e.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		confirm()
	elif e.keycode == KEY_ESCAPE:
		cancel()
	elif e.keycode >= KEY_1 and e.keycode <= KEY_9:
		toggle(e.keycode - KEY_1)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover = row_at(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var lay := layout()
		if lay["go"].has_point(e.position):
			confirm()
		elif lay["stay"].has_point(e.position):
			cancel()
		else:
			toggle(row_at(e.position))
	accept_event()


func row_at(p: Vector2) -> int:
	var rs: Array = layout()["rows"]
	for i in rs.size():
		if rs[i].has_point(p):
			return i
	return -1


## Where everything goes: {panel, rows, go, stay}.
func layout() -> Dictionary:
	var n := rows().size()
	var h := PAD + 52.0 + 64.0 + n * (ROW_H + 8.0) + 70.0 + PAD
	var panel := Rect2(((size - Vector2(WIDTH, h)) / 2.0).round(), Vector2(WIDTH, h))
	var out := {"panel": panel, "rows": []}
	var y := panel.position.y + PAD + 52.0 + 64.0
	for i in n:
		out["rows"].append(Rect2(Vector2(panel.position.x + PAD, y), Vector2(WIDTH - 2.0 * PAD, ROW_H)))
		y += ROW_H + 8.0
	out["go"] = Rect2(Vector2(panel.end.x - PAD - 240.0, y + 6.0), Vector2(240.0, 42.0))
	out["stay"] = Rect2(Vector2(panel.end.x - PAD - 240.0 - 200.0, y + 6.0), Vector2(180.0, 42.0))
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	var lay := layout()
	var p: Rect2 = lay["panel"]
	draw_rect(p, PANEL_BG)
	draw_rect(p, EDGE, false, 2.0)
	var kind := Expedition.kind_of(poi)
	var kc: Dictionary = Expedition.config()["kinds"].get(kind, {})
	var f := ThemeDB.fallback_font
	var x := p.position.x + PAD
	draw_string(f, Vector2(x, p.position.y + 40.0), ("Away team: %s" % str(poi.get("name", kc.get("label", "")))).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, AMBER)
	draw_string(f, Vector2(x, p.position.y + 70.0), str(kc.get("blurb", "")), HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 2.0 * PAD, 15, DIM_TEXT)
	var air := "No air: everyone needs a sealed suit to go far." if bool(kc.get("airless", false)) else "Pick 1 to %d. Gear they carry can be lost with them (I: crew kit)." % Expedition.team_max()
	draw_string(f, Vector2(x, p.position.y + 92.0), air, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 2.0 * PAD, 15, BAD if bool(kc.get("airless", false)) else TEXT)
	var rs := rows()
	for i in rs.size():
		var r: Rect2 = lay["rows"][i]
		var on: bool = pick.has(rs[i]["name"])
		draw_rect(r, ROW_BG)
		draw_rect(r, AMBER if on else (CYAN if i == hover else EDGE_DIM), false, 3.0 if on else 1.0)
		draw_string(f, r.position + Vector2(14.0, 24.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, AMBER)
		draw_string(f, r.position + Vector2(44.0, 24.0), "%s%s  (%s)  hp %d/%d" % [rs[i]["name"], " - the soldier" if rs[i]["soldier"] else "", str(rs[i]["species"]).capitalize(), roundi(rs[i]["hp"]), roundi(rs[i]["max_hp"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, TEXT)
		draw_string(f, r.position + Vector2(44.0, 48.0), str(rs[i]["gear"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 220.0, 14, DIM_TEXT)
		draw_string(f, r.position + Vector2(r.size.x - 170.0, 24.0), "SEALED" if rs[i]["sealed"] else "no suit", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GOOD if rs[i]["sealed"] else BAD)
		if on:
			draw_string(f, r.position + Vector2(r.size.x - 170.0, 48.0), "going", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, AMBER)
	if message != "":
		draw_string(f, Vector2(x, lay["go"].position.y + 28.0), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, BAD)
	for pair in [["go", "Send them (Enter)", AMBER if not pick.is_empty() else EDGE_DIM], ["stay", "Stay (Esc)", EDGE]]:
		var b: Rect2 = lay[pair[0]]
		draw_rect(b, ROW_BG)
		draw_rect(b, pair[2], false, 2.0)
		draw_string(f, b.position + Vector2(22.0, 28.0), pair[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, pair[2])
