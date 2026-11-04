extends RefCounted
## Loadouts (docs/BOARDING.md, B4): what a person carries aboard another vessel, set on the loadout screen at the airlock. Pure logic over a CrewMember's `kit`
## ({weapons: [weapon id, weapon id], body: item id, mods: [item id, item id]}; "" is an empty slot; an empty kit was never set) and the ship's hold.
## - What a person wears has left the hold, and goes back when it is taken off. A weapon slot holds a weapon id: the person's own sidearm (no item behind it)
##   or a hand weapon whose cargo item is in the hold (combat.hand_items). A crew member who is lost takes their kit with them.
## - Body gear is boarding.json `kit.bodies`; a person with the no_suit trait is refused it, with the reason (CrewMember.can_wear).
## - set_weapon, set_body and set_mod return "" when done, else why not; nothing changes then.

const Site = preload("res://scripts/board/site.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Mods = preload("res://scripts/board/mods.gd")


static func cfg() -> Dictionary:
	return Site.config()["kit"]


## The cargo item that is hand weapon `weapon` ("" for one that is no item: a species' own sidearm).
static func item_of(weapon: String) -> String:
	var items: Dictionary = Arms.cfg()["hand_items"]
	var keys: Array = items.keys()
	keys.sort()
	for item in keys:
		if str(items[item]) == weapon:
			return str(item)
	return ""


## The item that stands behind weapon `weapon` for person `m`: "" when it is their own sidearm.
static func _backing(m, weapon: String) -> String:
	return "" if weapon == "" or weapon == m.sidearm() else item_of(weapon)


## The kit of `m` with every list at its full length.
static func of(m) -> Dictionary:
	var k: Dictionary = m.kit
	var out := {"weapons": [], "body": str(k.get("body", "")), "mods": []}
	for i in int(cfg()["weapon_slots"]):
		out["weapons"].append(str(k["weapons"][i]) if k.get("weapons") is Array and i < k["weapons"].size() else "")
	for i in int(cfg()["mod_slots"]):
		out["mods"].append(str(k["mods"][i]) if k.get("mods") is Array and i < k["mods"].size() else "")
	return out


## Was the kit of `m` ever set (on the loadout screen)? A person with none boards with their sidearm and a spare hand weapon of the hold.
static func is_set(m) -> bool:
	return not m.kit.is_empty()


## The weapons `m` carries, in the order of the slots: the kit's (never empty: a kit with no weapon falls back to the sidearm), else just the sidearm.
static func weapons_of(m) -> Array:
	var out := []
	if is_set(m):
		for w in of(m)["weapons"]:
			if str(w) != "" and not Arms.weapon(str(w)).is_empty():
				out.append(str(w))
	if out.is_empty():
		out.append(m.sidearm())
	return out


## The share of the damage `m` takes aboard in their body gear (1.0 for none).
static func armor_mult(m) -> float:
	return float(Site.config()["armor"].get(str(m.kit.get("body", "")), 1.0))


## What body gear `item` does aboard, in words.
static func body_line(item: String) -> String:
	var share := float(Site.config()["armor"].get(item, 1.0))
	var sealed := bool(Site.config().get("gear", {}).get(item, {}).get("sealed", false))  # (air.gd: no airless room without one)
	if share >= 1.0:
		return "Sealed: breathe with no air." if sealed else "No use aboard."
	return "Takes %d%% less damage.%s" % [roundi((1.0 - share) * 100.0), " Sealed." if sealed else ""]


# --- changing a kit --------------------------------------------------------------------------------------------------------

static func _hold(ship, item: String) -> int:
	return ship.inventory.count(item) if ship != null else 99


static func _put(ship, item: String, n: int) -> void:
	if ship != null and item != "":
		ship.inventory.add(item, n)


## Give `m` the default kit if they have none: their sidearm, and with `spare` the first hand weapon the hold has (it leaves the hold).
static func materialize(ship, m, spare := false) -> void:
	if is_set(m):
		return
	m.kit = {"weapons": [m.sidearm(), ""], "body": "", "mods": ["", ""]}
	if spare and ship != null:
		var items: Dictionary = Arms.cfg()["hand_items"]
		var keys: Array = items.keys()
		keys.sort()
		for item in keys:
			if ship.inventory.count(item) > 0 and str(items[item]) != m.sidearm():
				m.kit["weapons"][1] = str(items[item])
				_put(ship, item, -1)
				break


## Put hand weapon `weapon` ("" empties the slot) in weapon slot `idx` of `m`.
static func set_weapon(ship, m, idx: int, weapon: String) -> String:
	if idx < 0 or idx >= int(cfg()["weapon_slots"]):
		return "No such slot."
	materialize(ship, m)
	var k := of(m)
	if weapon != "":
		if Arms.weapon(weapon).is_empty():
			return "Not a weapon."
		if k["weapons"].has(weapon) and k["weapons"][idx] != weapon:
			return "Already carried."
		var item := _backing(m, weapon)
		if weapon != m.sidearm() and item == "":
			return "That cannot be carried aboard."
		if k["weapons"][idx] != weapon and item != "" and _hold(ship, item) < 1:
			return "None in the hold."
	var old: String = k["weapons"][idx]
	if old == weapon:
		return ""
	_put(ship, _backing(m, old), 1)
	_put(ship, _backing(m, weapon), -1)
	k["weapons"][idx] = weapon
	m.kit = k
	return ""


## Dress `m` in body gear `item` ("" takes it off). The no_suit trait refuses it, with its reason.
static func set_body(ship, m, item: String) -> String:
	materialize(ship, m)
	var k := of(m)
	if item != "":
		if not cfg()["bodies"].has(item):
			return "Not body gear."
		var why: String = m.can_wear("suit")
		if why != "":
			return why
		if k["body"] != item and _hold(ship, item) < 1:
			return "None in the hold."
	var old: String = k["body"]
	if old == item:
		return ""
	_put(ship, old, 1)
	_put(ship, item, -1)
	k["body"] = item
	m.kit = k
	return ""


## Fit mod item `item` ("" empties the slot) into mod slot `idx` of `m`. One mod once per person.
static func set_mod(ship, m, idx: int, item: String) -> String:
	if idx < 0 or idx >= int(cfg()["mod_slots"]):
		return "No such slot."
	materialize(ship, m)
	var k := of(m)
	if item != "":
		var p := Mods.parse(item)
		if p.is_empty():
			return "Not a mod."
		for i in k["mods"].size():
			var q := Mods.parse(str(k["mods"][i]))
			if i != idx and not q.is_empty() and q["mod"] == p["mod"]:
				return "Already wearing a %s." % str(Mods.def(p["mod"])["name"])
		if k["mods"][idx] != item and _hold(ship, item) < 1:
			return "None in the hold."
	var old: String = k["mods"][idx]
	if old == item:
		return ""
	_put(ship, old, 1)
	_put(ship, item, -1)
	k["mods"][idx] = item
	m.kit = k
	return ""


## Take everything off `m`: the gear goes back to the hold, the sidearm stays.
static func strip(ship, m) -> void:
	if not is_set(m):
		return
	var k := of(m)
	for i in k["weapons"].size():
		_put(ship, _backing(m, str(k["weapons"][i])), 1)
	_put(ship, str(k["body"]), 1)
	for item in k["mods"]:
		_put(ship, str(item), 1)
	m.kit = {}


## `m` is gone from the ship for another reason than being left aboard a site (they bled out, they left): what they wore goes back to the hold. Returns the line for the
## chronicle ("Rook's kit is back in the hold."), "" when they carried nothing but a sidearm. (Lost aboard a site, the kit is lost with them: Mortality.lose.)
static func give_back(ship, m) -> String:
	var gear := carried_text(ship, m)
	strip(ship, m)
	return "%s's kit is back in the hold." % m.name if gear != "" else ""


## The items `m` carries, in words ("Carbine, Basic Armour, Spotter Cam Mk II"), "" for a sidearm alone: what is lost with them.
static func carried_text(ship, m) -> String:
	if not is_set(m):
		return ""
	var k := of(m)
	var out := []
	for w in k["weapons"]:
		if str(w) != "" and str(w) != m.sidearm():
			out.append(str(Arms.weapon(str(w)).get("name", w)))
	if str(k["body"]) != "":
		out.append(_name(ship, str(k["body"])))
	for item in k["mods"]:
		if str(item) != "":
			out.append(Mods.label(str(item)))
	return ", ".join(out)


static func _name(ship, item: String) -> String:
	return ship.crafting.name_of(item, ship.components) if ship != null else item.capitalize()


# --- what the loadout screen offers ---------------------------------------------------------------------------------------

## The choices for a slot of `m`: `slot` is "weapon", "body" or "mod". [{id (a weapon id or an item id, "" for empty), name, why (a short reason, "" when it can be taken: the
## set_ function says it in full), worn (it is what the slot holds now)}], the empty choice first. Only what the hold has (and what the slot holds now) is listed.
static func options(ship, m, slot: String, idx: int) -> Array:
	var k := of(m)
	var out := [{"id": "", "name": "Nothing", "why": "", "worn": slot_value(m, slot, idx) == ""}]
	match slot:
		"weapon":
			var ids := [m.sidearm()]
			var items: Dictionary = Arms.cfg()["hand_items"]
			var keys: Array = items.keys()
			keys.sort()
			for item in keys:
				if (_hold(ship, str(item)) > 0 or str(items[item]) == str(k["weapons"][idx])) and not ids.has(str(items[item])):
					ids.append(str(items[item]))
			for w in ids:
				var wd := Arms.weapon(str(w))
				if wd.is_empty():
					continue
				var why := ""
				if k["weapons"].has(w) and k["weapons"][idx] != w:
					why = "Already carried."
				out.append({"id": str(w), "name": str(wd["name"]), "why": why, "worn": k["weapons"][idx] == w})
		"body":
			for item in cfg()["bodies"]:
				if _hold(ship, str(item)) > 0 or k["body"] == item:
					out.append({"id": str(item), "name": _name(ship, str(item)), "why": "Can't wear it." if m.can_wear("suit") != "" else "", "worn": k["body"] == item})
		"mod":
			var held: Array = []
			if ship != null:
				for row in ship.inventory.counts:
					if Mods.is_item(str(row)):
						held.append(str(row))
			if str(k["mods"][idx]) != "" and not held.has(str(k["mods"][idx])):
				held.append(str(k["mods"][idx]))
			held.sort()
			for item in held:
				if _hold(ship, str(item)) < 1 and k["mods"][idx] != item:
					continue
				var p := Mods.parse(str(item))
				var why := ""
				for i in k["mods"].size():
					var q := Mods.parse(str(k["mods"][i]))
					if i != idx and not q.is_empty() and q["mod"] == p["mod"]:
						why = "Already worn."
				out.append({"id": str(item), "name": Mods.label(str(item)), "why": why, "worn": k["mods"][idx] == item})
	return out


## What slot `idx` of `slot` ("weapon", "body", "mod") of `m` holds now: a weapon id or an item id, "" for empty. An unset kit shows the sidearm in the first weapon slot.
static func slot_value(m, slot: String, idx: int) -> String:
	if not is_set(m):
		return m.sidearm() if slot == "weapon" and idx == 0 else ""
	var k := of(m)
	match slot:
		"weapon":
			return str(k["weapons"][idx])
		"body":
			return str(k["body"])
	return str(k["mods"][idx])
