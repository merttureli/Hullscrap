extends RefCounted
## The loadout screen (docs/BOARDING.md, B4), the airlock's crew picker grown up. Drawn on the HUD (board_hud.gd) while the view is `picking`:
## - left: the soldier and the crew who can come (pick up to party_max, as before);
## - right: for the person shown, their weapons (two slots), body gear (one) and mods (two). A click on a slot lists what the hold has for it; a click on a choice
##   takes it (kit.gd moves the item out of the hold, and back when it is taken off). A refusal says why (a person who cannot wear a suit is told so).
## The mouse clicks come back as the hits the HUD registered (hud.hit_add): {type: "go" | "pick" | "person" | "slot" | "option", ...}; board_view.gd acts on them.

const Arms = preload("res://scripts/board/arms.gd")
const Kit = preload("res://scripts/board/kit.gd")
const Mods = preload("res://scripts/board/mods.gd")
const Cards = preload("res://scripts/board/board_cards.gd")
const Describe = preload("res://scripts/ui/describe.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const PW := 1040.0
const PH := 620.0
const ROW := 34.0
const PICK_ROW := 52.0  ## a crew row of the picker: name and hp, then their gear and rounds
const OPT_ROW := 46.0  ## a choice: its name, and under it the stats line
const SLOT := Vector2(190, 54)


static func draw(h, size: Vector2) -> void:
	var v = h.view
	var r := Rect2(size / 2.0 - Vector2(PW, PH) / 2.0, Vector2(PW, PH))
	h.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	h.draw_rect(r, Color(h.PANEL_BG, 0.97))
	h.draw_rect(r, h.EDGE, false, 2.0)
	h._text("Boarding party", r.position + Vector2(20, 36), 24, h.TEXT)
	h._text("Take up to %d crew along, or go alone, and set what each carries. Crew who are down when you leave are lost, with their kit." % int(Arms.cfg()["party_max"]), r.position + Vector2(20, 58), 13, h.DIM_TEXT)
	var people: Array = v.loadout_people()
	_crew(h, r, v, people)
	if not people.is_empty():
		_person(h, Rect2(r.position + Vector2(316, 74), Vector2(PW - 336, PH - 150)), v, people[mini(v.load_who, people.size() - 1)])
	var go := Rect2(r.end - Vector2(196, 52), Vector2(176, 34))
	h.draw_rect(go, Color(h.AIRLOCK, 0.35))
	h.draw_rect(go, h.AIRLOCK, false, 1.5)
	var n := people.size() - 1
	h._text("Go aboard" if n <= 0 else "Go aboard (+%d)" % n, go.position + Vector2(24, 23), 18, h.TEXT)
	h.hit_add(go, {"type": "go"})
	var alone := Rect2(go.position - Vector2(136, 0), Vector2(124, 34))
	h.draw_rect(alone, Color(h.AMBER, 0.2))
	h.draw_rect(alone, h.AMBER, false, 1.5)
	h._text("Go alone", alone.position + Vector2(20, 23), 18, h.TEXT)
	h.hit_add(alone, {"type": "alone"})
	h._text("Click a crew row, or press its number, to bring them. Click a slot to set a kit.", r.position + Vector2(20, PH - 36), 13, h.DIM_TEXT)
	h._text("Tab: next person    Enter: go aboard    A or Esc: go alone", r.position + Vector2(20, PH - 18), 13, h.DIM_TEXT)
	if str(v.load_msg) != "":
		h._text(str(v.load_msg), r.position + Vector2(316, PH - 62), 15, h.BAD)


## The soldier and the crew who can come: each row has the hp, the species, the gear and the rounds they would carry; "no suit" when the rules mark suits that seal
## and they wear none (nothing is shown while no suit is marked).
static func _crew(h, r: Rect2, v, people: Array) -> void:
	var rows: Array = v.pick_rows()
	var cap := int(Arms.cfg()["party_max"])
	h._text("CREW", r.position + Vector2(20, 96), 12, h.DIM_TEXT)
	var count := "%d of %d" % [v.pick.size(), cap]
	h._text(count, r.position + Vector2(300.0 - h._font().get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, 96), 13, h.AMBER if v.pick.size() >= cap else h.DIM_TEXT)
	var y := r.position.y + 106.0
	var soldier = v._src_soldier()
	if soldier != null:
		var rr := Rect2(r.position.x + 16.0, y, 284.0, ROW - 4.0)
		_row(h, rr, v.load_who == 0, false)
		h._text("%s   You" % soldier.name, rr.position + Vector2(34, 22), 16, h.TEXT)
		h._text("%d/%d" % [ceili(soldier.hp), roundi(soldier.max_hp)], rr.position + Vector2(rr.size.x - 56, 22), 14, h.DIM_TEXT)
		h.hit_add(rr, {"type": "person", "i": 0})
		y += ROW
	if rows.is_empty():
		h._text("Nobody else can come:", Vector2(r.position.x + 20.0, y + 20.0), 14, h.DIM_TEXT)
		h._text("crew at a post, down, or none yet.", Vector2(r.position.x + 20.0, y + 38.0), 12, h.DIM_TEXT)
	for i in rows.size():
		var rr2 := Rect2(r.position.x + 16.0, y, 284.0, PICK_ROW - 4.0)
		var picked: bool = v.pick.has(rows[i]["name"])
		var idx := -1
		for k in people.size():
			if people[k].name == rows[i]["name"]:
				idx = k
		_row(h, rr2, picked and v.load_who == idx, picked)
		h._text("%d" % (i + 1), rr2.position + Vector2(10, 22), 14, h.DIM_TEXT)
		h._text("%s   %s" % [rows[i]["name"], str(rows[i]["species"]).capitalize()], rr2.position + Vector2(34, 22), 16, h.TEXT)
		h._text("%d/%d" % [roundi(rows[i]["hp"]), roundi(rows[i]["max_hp"])], rr2.position + Vector2(rr2.size.x - 56, 22), 14, h.DIM_TEXT)
		var line := str(rows[i]["gear"])
		if int(rows[i]["rounds"]) >= 0:
			line += "   %d rounds" % int(rows[i]["rounds"])
		h._text(line, rr2.position + Vector2(34, 40), 12, h.DIM_TEXT)
		if bool(rows[i]["no_suit"]):
			var tag := "no suit"
			var tw: float = h._font().get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			h._text(tag, rr2.position + Vector2(rr2.size.x - tw - 8.0, 40), 12, h.AMBER)
		h.hit_add(Rect2(rr2.position, Vector2(30, rr2.size.y)), {"type": "pick", "i": i})
		h.hit_add(rr2, {"type": "person", "i": idx} if picked else {"type": "pick", "i": i})
		y += PICK_ROW


static func _row(h, rr: Rect2, shown: bool, picked: bool) -> void:
	h.draw_rect(rr, Color(h.GOOD, 0.3) if shown else (Color(h.GOOD, 0.14) if picked else h.ROW_BG))
	if shown:
		h.draw_rect(rr, h.GOOD, false, 1.5)


## The person whose kit is shown: the head, the name, and the slots.
static func _person(h, area: Rect2, v, m) -> void:
	Cards._portrait(h, Rect2(area.position, Vector2(56, 56)), m)
	h._text("%s   %s" % [m.name, str(m.species).capitalize()], area.position + Vector2(70, 24), 20, h.TEXT)
	var bar := Rect2(area.position + Vector2(70, 34), Vector2(220, 8))
	var f := clampf(m.hp / maxf(m.max_hp, 1.0), 0.0, 1.0)
	h.draw_rect(bar, h.ROW_BG)
	h.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), h.GOOD if f > 0.5 else (h.AMBER if f > 0.25 else h.BAD))
	h._text("%d/%d hp" % [ceili(m.hp), roundi(m.max_hp)], area.position + Vector2(300, 43), 13, h.DIM_TEXT)
	var kit: Dictionary = Kit.of(m)
	var ship = v.session.ship
	var x := area.position.x
	var y := area.position.y + 78.0
	_label(h, "WEAPONS", Vector2(x, y + 14.0), v.weapons_note())
	for i in kit["weapons"].size():
		var w := str(kit["weapons"][i])
		var wd := Arms.weapon(w) if w != "" else {}
		_slot(h, v, Rect2(x + float(i) * (SLOT.x + 12.0), y + 22.0, SLOT.x, SLOT.y), "weapon", i, "", str(wd.get("name", "")), \
			"%s, %d dmg" % [str(wd.get("class", "")).capitalize(), roundi(float(wd.get("damage", 0)))] if w != "" else "", str(wd.get("art", "")), Cards._weapon_lines(w) if w != "" else [], h.TEXT)
	y += 96.0
	_label(h, "BODY", Vector2(x, y + 14.0), "Armour takes damage off. Sealed suits work with no air.")
	var body := str(kit["body"])
	_slot(h, v, Rect2(x, y + 22.0, SLOT.x, SLOT.y), "body", 0, body, _name(ship, body) if body != "" else "", body_sub(body) if body != "" else "", "", \
		["Body gear", Kit.body_line(body)] if body != "" else [], h.TEXT)
	y += 96.0
	_label(h, "MODS", Vector2(x, y + 14.0), "")
	var chip := Describe.keyword("mod")
	var cr := Rect2(Vector2(x + 52.0, y + 1.0), Vector2(UiKit.text_width(chip["label"], 11, UiKit.bold()) + 10.0, 18))
	UiKit.keyword_chip(h, cr, chip, 11, false)
	h.hover_add(cr, [str(chip["hover"])], chip["color"])
	for i in kit["mods"].size():
		var item := str(kit["mods"][i])
		var p := Mods.parse(item)
		_slot(h, v, Rect2(x + float(i) * (SLOT.x + 12.0), y + 22.0, SLOT.x, SLOT.y), "mod", i, item, str(Mods.def(p["mod"])["name"]) if item != "" else "", \
			str(Mods.config()["tier_names"][int(p["tier"]) - 1]) if item != "" else "", "", Mods.hover(item) if item != "" else [], Mods.color(p["mod"]) if item != "" else h.TEXT)
	if not v.load_slot.is_empty():
		var ox := x + 2.0 * (SLOT.x + 12.0) + 16.0
		_options(h, v, Rect2(ox, area.position.y + 70.0, area.end.x - ox, area.size.y - 70.0))


## The line under a body gear's name in its slot: what it does without "Takes" (the whole sentence ran over the slot's edge; the hover has it).
static func body_sub(item: String) -> String:
	var own := str(Kit.gear_def(item).get("sub", ""))
	if own != "":
		return own
	var line := Kit.body_line(item).trim_prefix("Takes ")
	if line.ends_with(" Sealed."):  # the slot is narrow
		return line.trim_suffix(" damage. Sealed.") + " dmg, sealed"
	return "Sealed for no air." if line.begins_with("Sealed") else line


static func _label(h, text: String, at: Vector2, note: String) -> void:
	h._text(text, at, 12, h.DIM_TEXT)
	if note != "":
		h._text(note, at + Vector2(0, 0) + Vector2(70, 0), 12, Color(h.DIM_TEXT, 0.75))


## One slot: its icon, a name and a line under it; lit when its choices are listed.
static func _slot(h, v, r: Rect2, slot: String, idx: int, item: String, title: String, sub: String, art: String, lines: Array, col: Color) -> void:
	var open: bool = not v.load_slot.is_empty() and v.load_slot["slot"] == slot and int(v.load_slot["idx"]) == idx
	h.draw_rect(r, h.ROW_BG)
	h.draw_rect(r, h.AMBER if open else h.EDGE_DIM, false, 2.0 if open else 1.0)
	var ir := Rect2(r.position + Vector2(8, 8), Vector2(38, 38))
	h.draw_rect(ir, Color(h.PANEL_BG, 0.9))
	if title == "":
		h._text("empty", r.position + Vector2(56, 32), 15, h.DIM_TEXT)
	else:
		match slot:
			"mod":
				Mods.draw_icon(h, item, ir)
			"body":
				Cards._body_icon(h, ir, item)
			_:
				Cards._art(h, art, ir.grow(-3.0), 1.0)
		h._text(title, r.position + Vector2(54, 24), 14, col)
		h._text(sub, r.position + Vector2(54, 43), 12, h.DIM_TEXT)
		h.hover_add(r, lines, col if slot == "mod" else h.EDGE)
	h.hit_add(r, {"type": "slot", "slot": slot, "idx": idx})


## The choices of the open slot, numbered (keys 1-9 pick the first nine); as many rows as the panel's height holds.
static func _options(h, v, r: Rect2) -> void:
	var opts: Array = v.loadout_options()
	var rows := minf(float(opts.size()), floorf((r.size.y - 38.0) / OPT_ROW))
	var box := Rect2(r.position, Vector2(r.size.x, 34.0 + rows * OPT_ROW))
	h.draw_rect(box, Color(h.PANEL_BG, 0.99))
	h.draw_rect(box, h.AMBER, false, 1.5)
	h._text("Choose", box.position + Vector2(12, 22), 14, h.AMBER)
	for i in int(rows):
		var o: Dictionary = opts[i]
		var rr := Rect2(box.position + Vector2(8, 30.0 + float(i) * OPT_ROW), Vector2(box.size.x - 16, OPT_ROW - 4))
		h.draw_rect(rr, Color(h.GOOD, 0.22) if bool(o["worn"]) else h.ROW_BG)
		h._text("%d" % (i + 1), rr.position + Vector2(8, 22), 13, h.DIM_TEXT)
		var col: Color = h.TEXT if str(o["why"]) == "" else h.DIM_TEXT
		var id := str(o["id"])
		if str(v.load_slot["slot"]) == "mod" and id != "":
			Mods.draw_icon(h, id, Rect2(rr.position + Vector2(26, 3), Vector2(22, 22)))
			col = Mods.color(Mods.parse(id)["mod"]) if str(o["why"]) == "" else col
		h._text(str(o["name"]), rr.position + Vector2(56, 20), 15, col)
		h._text(stats(str(v.load_slot["slot"]), id), rr.position + Vector2(56, 38), 12, h.DIM_TEXT)
		if str(o["why"]) != "":
			var w: float = h._font().get_string_size(str(o["why"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			h._text(str(o["why"]), Vector2(rr.end.x - w - 8.0, rr.position.y + 20.0), 12, h.BAD)
		elif bool(o["worn"]) and id != "":
			h._text("worn", Vector2(rr.end.x - 40.0, rr.position.y + 20.0), 12, h.GOOD)
		h.hit_add(rr, {"type": "option", "i": i})
		if id != "":
			var lines: Array = []
			match str(v.load_slot["slot"]):
				"weapon":
					lines = Cards._weapon_lines(id)
				"body":
					lines = [str(o["name"]), Kit.body_line(id)]
				"mod":
					lines = Mods.hover(id)
			h.hover_add(rr, lines, h.EDGE)


## The stats line under a choice (and in a hold row): the same words as the slot's hover. "" for the empty choice or a "give to" row.
static func stats(slot: String, id: String) -> String:
	if id == "" or id.begins_with("give:"):
		return ""
	match slot:
		"weapon":
			var l: Array = Cards._weapon_lines(id)
			return str(l[1]) if l.size() > 1 else ""
		"body":
			var own := str(Kit.gear_def(id).get("sub", ""))  # (the whole sentence runs over a choice's row: the hover has it)
			return own if own != "" else Kit.body_line(id)
		"mod":
			var l2: Array = Mods.hover(id)
			return str(l2[1]) if l2.size() > 1 else ""
	return ""


static func _name(ship, item: String) -> String:
	return ship.crafting.name_of(item, ship.components) if ship != null else item.capitalize()
