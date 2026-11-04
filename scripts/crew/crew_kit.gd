extends RefCounted
## The crew equipment screen's rules (I in play mode, scripts/ui/crew_kit_panel.gd draws it): what the crew carry, set while the ship flies. The same kits as the
## airlock loadout (scripts/board/kit.gd: weapons x2, body x1, mods x2; what is worn has left the hold), so it is that script that decides what fits and why not.
## This one adds the screen's own state (who is shown, which slot is open), the hold's list of gear, and moving an item from one crew member to another.
## It holds the same names as the boarding view's loadout (load_who, load_slot, load_msg, session.ship, loadout_options()) so board_loadout.gd draws both.

const Kit = preload("res://scripts/board/kit.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Mods = preload("res://scripts/board/mods.gd")

var session:  ## (the loadout drawing asks for `v.session.ship`: this is its own session)
	get:
		return self
var ship  ## the player's Ship
var load_who := 0  ## index into people()
var load_slot := {}  ## {slot: "weapon" | "body" | "mod", idx} of the slot whose choices are listed, {} for none
var load_msg := ""  ## why the last choice was refused


func _init(p_ship = null) -> void:
	ship = p_ship


## Who the screen sets: every crew member but the repair drones, the soldier first.
func people() -> Array:
	var out := []
	if ship == null:
		return out
	for m in ship.crew:
		if not m.is_drone():
			out.append(m)
	out.sort_custom(func(a, b): return a.is_player and not b.is_player)
	return out


## The person shown (null when there is nobody).
func person():
	var p := people()
	return p[clampi(load_who, 0, p.size() - 1)] if not p.is_empty() else null


func focus(i: int) -> void:
	load_who = clampi(i, 0, maxi(people().size() - 1, 0))
	load_slot = {}
	load_msg = ""


## Open the choices of a slot of the person shown; the same slot again shuts them.
func open_slot(slot: String, idx: int) -> void:
	load_msg = ""
	if load_slot.get("slot", "") == slot and int(load_slot.get("idx", -1)) == idx:
		load_slot = {}
	else:
		load_slot = {"slot": slot, "idx": idx}


## The choices of the open slot: Kit.options (the empty choice first: take it off, back to the hold), then, for a slot that holds something, one "Give to <name>"
## for every other crew member ({id: "give:<name>", name, why, worn: false}).
func loadout_options() -> Array:
	var m = person()
	if load_slot.is_empty() or m == null:
		return []
	var slot := str(load_slot["slot"])
	var idx := int(load_slot["idx"])
	var out := Kit.options(ship, m, slot, idx)
	if Kit.slot_value(m, slot, idx) != "" and not _own_sidearm(m, slot, idx):
		for o in people():
			if o != m:
				out.append({"id": "give:" + o.name, "name": "Give to %s" % o.name, "why": "", "worn": false})
	return out


## Take choice `i` of the open slot. Returns why not ("" when done); the reason is also kept in load_msg.
func choose(i: int) -> String:
	var opts := loadout_options()
	var m = person()
	if i < 0 or i >= opts.size() or m == null:
		return ""
	var id := str(opts[i]["id"])
	var slot := str(load_slot["slot"])
	var idx := int(load_slot["idx"])
	var why := ""
	if id.begins_with("give:"):
		var to = _named(id.trim_prefix("give:"))
		why = move(ship, m, slot, idx, to) if to != null else "Nobody by that name."
	else:
		why = set_slot(ship, m, slot, idx, id)
	load_msg = why
	if why == "":
		load_slot = {}
	return why


func _named(name: String):
	for m in people():
		if m.name == name:
			return m
	return null


# --- the rules --------------------------------------------------------------------------------------------------------------

static func _own_sidearm(m, slot: String, idx: int) -> bool:
	return slot == "weapon" and Kit.slot_value(m, slot, idx) == m.sidearm()


## Put `id` ("" empties the slot) in the slot of `m`. "" when done, else why not (Kit's own words: a person who cannot wear a suit is told so).
static func set_slot(ship, m, slot: String, idx: int, id: String) -> String:
	match slot:
		"weapon":
			return Kit.set_weapon(ship, m, idx, id)
		"body":
			return Kit.set_body(ship, m, id)
		"mod":
			return Kit.set_mod(ship, m, idx, id)
	return "No such slot."


## The first slot of `m` that `id` (a weapon id, body gear or a mod item) could go in: {slot, idx}, {} when none is free. A free slot is the first empty one.
static func free_slot_for(m, id: String) -> Dictionary:
	var kind := kind_of(id)
	match kind:
		"weapon":
			for i in int(Kit.cfg()["weapon_slots"]):
				if Kit.slot_value(m, "weapon", i) == "":
					return {"slot": "weapon", "idx": i}
		"body":
			if Kit.slot_value(m, "body", 0) == "":
				return {"slot": "body", "idx": 0}
		"mod":
			for i in int(Kit.cfg()["mod_slots"]):
				if Kit.slot_value(m, "mod", i) == "":
					return {"slot": "mod", "idx": i}
	return {}


## What kind of gear `id` is: "weapon" (a weapon id), "body", "mod", else "".
static func kind_of(id: String) -> String:
	if Kit.cfg()["bodies"].has(id):
		return "body"
	if Mods.is_item(id):
		return "mod"
	if not Arms.weapon(id).is_empty():
		return "weapon"
	return ""


## Give `m` the gear `id` of the hold in the first free slot it fits (a weapon, a body or a mod); a refusal says why. "" when done.
static func equip_from_hold(ship, m, id: String) -> String:
	var where := free_slot_for(m, id)
	if where.is_empty() and kind_of(id) == "body":
		where = {"slot": "body", "idx": 0}  # (one body slot: the new gear replaces the old, which goes back to the hold)
	if where.is_empty():
		return "%s has no free slot for that: click a slot to replace what is in it." % m.name
	return set_slot(ship, m, str(where["slot"]), int(where["idx"]), id)


## Move what slot `idx` of `slot` holds on `from` to `to`, to a free slot of theirs: out of the first (back to the hold) and into the second. A refusal (no_suit,
## no free slot, a mod worn twice) changes nothing and says why. "" when done.
static func move(ship, from, slot: String, idx: int, to) -> String:
	if from == to or to == null:
		return "Nothing to do."
	var id := Kit.slot_value(from, slot, idx)
	if id == "" or _own_sidearm(from, slot, idx):
		return "Their own sidearm stays with them." if id != "" else "Nothing there."
	var where := free_slot_for(to, id)
	if where.is_empty():
		return "%s has no free slot for that." % to.name
	var why := set_slot(ship, from, slot, idx, "")
	if why != "":
		return why
	why = set_slot(ship, to, str(where["slot"]), int(where["idx"]), id)
	if why != "":
		set_slot(ship, from, slot, idx, id)  # (it goes back where it was)
	return why


## The gear in the hold, for the screen's list: [{id, kind, name, count}], weapons then body gear then mods.
static func hold_rows(ship) -> Array:
	var out := []
	if ship == null:
		return out
	var items: Dictionary = Arms.cfg()["hand_items"]
	var keys: Array = items.keys()
	keys.sort()
	for item in keys:
		var n: int = ship.inventory.count(str(item))
		var wd := Arms.weapon(str(items[item]))
		if n > 0 and not wd.is_empty():
			out.append({"id": str(items[item]), "kind": "weapon", "name": str(wd["name"]), "count": n})
	for item in Kit.cfg()["bodies"]:
		var n2: int = ship.inventory.count(str(item))
		if n2 > 0:
			out.append({"id": str(item), "kind": "body", "name": ship.crafting.name_of(str(item), ship.components), "count": n2})
	var mods: Array = []
	for row in ship.inventory.counts:
		if Mods.is_item(str(row)) and ship.inventory.count(str(row)) > 0:
			mods.append(str(row))
	mods.sort()
	for item in mods:
		out.append({"id": item, "kind": "mod", "name": Mods.label(item), "count": ship.inventory.count(item)})
	return out
