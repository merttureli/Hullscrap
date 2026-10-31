extends RefCounted
## Cutting a beaten ship apart (docs/MECHANICS_REVIEW.md P3): the loot of a fight is the enemy's real,
## surviving parts, and the player picks one of a few ("pick 1 of 3"). event_for() builds an event
## dictionary the event panel shows as it is (id `salvage`): one row to cut out each of up to 3 parts (4 when
## the ship was captured whole), one row to scan the best part whose blueprint is unknown, and, after a plain
## win, a row to strip her for scrap. Parts the fight wrecked are no longer on the ship, so they are not offered.
## No nodes, no drawing. All the random picks use the campaign's rng; the numbers are in data/drift.json `loot`.
## `c` below is the campaign (campaign.gd; not preloaded here, to avoid a cycle) and `ship` the player's Ship.

const NOT_OFFERED: Array = ["bed", "helm"]  ## families and ids nobody cuts out of a wreck
const PICKS := {"won": 3, "captured": 4}  ## parts offered by the state of the fight
const DANGEROUS_TEXT := " She was dangerous. There's more worth cutting."  ## added to the page when the threat bonus gave more rows


## The ids of the parts still on `enemy` that can be cut out, one entry per part (a ship with two engines
## lists the engine twice), sorted. No bed, no helm, nothing the fight wrecked (those are off the ship already).
static func parts(enemy) -> Array:
	var out := []
	if enemy == null:
		return out
	for inst in enemy.components.instances.values():
		var id := str(inst["id"])
		if not NOT_OFFERED.has(id) and not NOT_OFFERED.has(str(enemy.components.def(id).get("family", ""))):
			out.append(id)
	out.sort()
	return out


## The parts offered after a fight in `state` against an enemy of `threat` skulls: the state's base, plus the bonus of
## data/drift.json `loot.threat_picks` ({"4": 1, "5": 2}: a dangerous enemy pays better).
static func picks_for(state: String, threat: int, c) -> int:
	var bonus: Dictionary = c.cfg["loot"].get("threat_picks", {})
	return int(PICKS.get(state, PICKS["won"])) + int(bonus.get(str(clampi(threat, 0, 5)), 0))


## The scrap a stripped ship gives: (strip_base + strip_per_part x its parts) x the tier (data/drift.json loot); half
## of that from a ghost ship, one the Hollow tide sent (`hollow`, docs/MECHANICS_REVIEW.md P1).
static func strip_scrap(enemy, c, hollow := false) -> int:
	var l: Dictionary = c.cfg["loot"]
	var scrap: int = (int(l["strip_base"]) + int(l["strip_per_part"]) * parts(enemy).size()) * c.tier()
	return maxi(scrap / 2, 1) if hollow else scrap


## The recipe that makes item `item` ("" when none does): the recipe of that id, else the first one that outputs it.
static func recipe_for(ship, item: String) -> String:
	if ship.crafting.has(item) and ship.crafting.def(item)["output"]["item"] == item:
		return item
	for rid in ship.crafting.order:
		if ship.crafting.def(rid)["output"]["item"] == item:
			return rid
	return ""


## The salvage event for `enemy` (its Ship, as the fight left it) after a fight in `state` ("won" or "captured").
## Returns {} when there is nothing to offer. Rows, in order: "Cut out the X" (the part, to the cargo), at
## most one "Scan the X" (its blueprint: the highest-tier offered part whose recipe the ship does not know),
## and for a win "Strip her for scrap". A captured ship's scrap was paid already (Campaign.fight_done).
## A ghost ship (`hollow`: it came from a place the Hollow tide has taken, which is what the campaign says when the
## flag is left out) offers only the strip row, at half the scrap, whatever the state: nothing aboard is worth cutting
## out or scanning, and its scrap was not paid at the fight. `threat` (1-5 skulls, 0 when unknown) adds parts to the
## pick (picks_for) and a line to the page when that gave more rows.
static func event_for(enemy, state: String, c, ship, hollow = null, threat := 0) -> Dictionary:
	var ghost: bool = c.is_hollow(c.current) if hollow == null else bool(hollow)
	if ghost:
		return _ghost_event(enemy, c)
	var pool := []
	for id in parts(enemy):
		if not pool.has(id):
			pool.append(id)
	var picked := []
	var base := int(PICKS.get(state, PICKS["won"]))
	for i in picks_for(state, threat, c):
		if pool.is_empty():
			break
		picked.append(pool.pop_at(c.rng.randi() % pool.size()))
	picked.sort()
	var choices := []
	for id in picked:
		var nm := _name(ship, id)
		choices.append(_row("Cut out the %s" % nm, "The cutters bite through the mounts and the %s comes free." % nm, {"items": {id: 1}}))
	var scan := ""  # the part to scan: the highest tier, the first of equals
	for id in picked:
		if recipe_for(ship, id) != "" and not ship.crafting.is_known(recipe_for(ship, id)) and (scan == "" or _tier(ship, id) > _tier(ship, scan)):
			scan = id
	if scan != "":
		choices.append(_row("Scan the %s (learn its blueprint)" % _name(ship, scan), "The scanner maps every weld and wire of the %s." % _name(ship, scan), {"blueprint": [recipe_for(ship, scan)]}))
	var foe := str(enemy.name) if enemy != null else "ship"
	var text := "Nobody is left standing aboard the %s. Your crew strip her hold, then pick one prize to cut loose." % foe
	var more := DANGEROUS_TEXT if picked.size() > base else ""
	if state != "captured":
		var scrap := strip_scrap(enemy, c)
		choices.append(_row("Strip her for scrap (+%d)" % scrap, "You cut her down to the frame. What is left breaks up behind you.", {"items": {"scrap": scrap}}))
		text = "The %s hangs dead, venting. Your cutters have time for one job before she breaks up." % foe
	text += more
	if choices.is_empty():
		return {}
	return {"id": "salvage", "type": "salvage", "once": false, "title": "Salvage: %s" % foe, "text": text, "choices": choices}


## The salvage of a ghost ship: one row, the plating at half the scrap.
static func _ghost_event(enemy, c) -> Dictionary:
	var foe := str(enemy.name) if enemy != null else "ship"
	var scrap := strip_scrap(enemy, c, true)
	var row := _row("Strip her for scrap (+%d)" % scrap, "Nothing aboard is right. Your cutters take the plating and leave the rest.", {"items": {"scrap": scrap}})
	return {"id": "salvage", "type": "salvage", "once": false, "title": "Salvage: %s" % foe,
		"text": "The %s drifts with no light in her and no crew to show for it. She will not last long. Your cutters have time for the plating." % foe, "choices": [row]}


static func _row(text: String, outcome_text: String, effects: Dictionary) -> Dictionary:
	return {"text": text, "outcomes": [{"weight": 1, "text": outcome_text, "effects": effects}]}


static func _name(ship, id: String) -> String:
	return ship.crafting.name_of(id, ship.components)


static func _tier(ship, id: String) -> int:
	return int(ship.components.def(id).get("tier", 1))
