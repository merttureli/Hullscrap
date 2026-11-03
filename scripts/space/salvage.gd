extends RefCounted
## Cutting a beaten ship apart (docs/MECHANICS_REVIEW.md P3): the loot of a fight is the enemy's real,
## surviving parts, and the player picks one of a few ("pick 1 of 3"). event_for() builds an event
## dictionary the event panel shows as it is (id `salvage`): one row to cut out each of up to 3 parts (4 when
## the ship was captured whole), one row to scan the part whose blueprint the ship can use next (next_recipe), and, after a plain
## win, a row to strip her for scrap. Parts the fight wrecked are no longer on the ship, so they are not offered.
## A crew member with loot_bonus adds rows to the pick (picks_for). No nodes, no drawing. All the random picks use the campaign's rng; the numbers are in data/drift.json `loot`.
## `c` below is the campaign (campaign.gd; not preloaded here, to avoid a cycle) and `ship` the player's Ship.

const TraitSet = preload("res://scripts/crew/traits.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Content = preload("res://scripts/data/content.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")
const Processing = preload("res://scripts/craft/processing.gd")

const OTHER := 3  ## next_recipe: the class of every recipe that is not a module, a weapon or a shield
const NOT_OFFERED: Array = ["bed", "helm"]  ## families and ids nobody cuts out of a wreck
const PICKS := {"won": 3, "captured": 4, "spared": 1}  ## parts offered by the state of the fight (a spared ship hands over one, and has no strip row)
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
## data/drift.json `loot.threat_picks` ({"4": 1, "5": 2}: a dangerous enemy pays better), plus the best loot_bonus aboard `ship`
## (TraitSet.loot_bonus; no ship, no bonus).
static func picks_for(state: String, threat: int, c, ship = null) -> int:
	if state == "spared":  # one pick, whatever the threat or the crew
		return int(PICKS["spared"])
	var bonus: Dictionary = c.cfg["loot"].get("threat_picks", {})
	return int(PICKS.get(state, PICKS["won"])) + int(bonus.get(str(clampi(threat, 0, 5)), 0)) + TraitSet.loot_bonus(ship)


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


## The recipe among `ids` the ship can craft next, "" when none can be (the Scan row of a salvage and a boarding blueprint share this pick).
## A candidate is unknown, not a material, and within reach of its station: the level it asks is at most the station's level + 1 (the fabricator,
## or the smelter for a smelter recipe) and each tool it asks is on the station or its recipe is known (the ship can build it). Of those the
## fabricator modules come first (they open the next level), then the weapons and shields of the core game, then those of the racial packs, the
## higher tier first in each; only when there are none, other parts by tier, the top tier on offer left out while a lower one remains (the next
## step, not the far prize). Equals: the first by id, or one drawn with `rng` when it is given.
static func next_recipe(ship, ids: Array, rng = null) -> String:
	var stations := {}  # station -> {level, tools}, looked up once
	var cands := []
	for v in ids:
		var rid := str(v)
		if not ship.crafting.has(rid) or ship.crafting.is_known(rid) or cands.has(rid):
			continue
		var r: Dictionary = ship.crafting.def(rid)
		if str(r.get("category", "")) == "material":
			continue
		var st := str(r["station"])
		if not stations.has(st):
			stations[st] = Workshop.best(ship) if st == "fabricator" else Processing.best(ship, st)
		var have: Dictionary = stations[st]
		if int(r["fab_level"]) > int(have["level"]) + 1:
			continue
		if r["tools"].any(func(t): return not have["tools"].has(t) and not ship.crafting.is_known(str(t))):
			continue
		cands.append(rid)
	var pool: Array = cands.filter(func(x): return _recipe_class(ship, x) < OTHER)
	if pool.is_empty():
		pool = cands
		var top := 0
		for rid in cands:
			top = maxi(top, _recipe_tier(ship, rid))
		var lower: Array = cands.filter(func(x): return _recipe_tier(ship, x) < top)
		if not lower.is_empty():
			pool = lower
	var best_score := 1 << 30
	var best := []
	for rid in pool:
		var score := _recipe_class(ship, rid) * 100 - _recipe_tier(ship, rid)
		if score < best_score:
			best_score = score
			best = []
		if score == best_score:
			best.append(rid)
	if best.is_empty():
		return ""
	best.sort()
	return str(best[0] if rng == null else best[rng.randi() % best.size()])


## How much next_recipe wants recipe `rid`: 0 a fabricator module, 1 a weapon or shield of the core game, 2 one of a racial pack (tech_*), OTHER the rest.
static func _recipe_class(ship, rid: String) -> int:
	var item := str(ship.crafting.def(rid)["output"]["item"])
	var family := str(ship.components.def(item).get("family", ""))
	if family == "workshop":
		return 0
	if family == "weapon" or family == "shield":
		return 2 if Content.origin("components", item).begins_with("tech_") else 1
	return OTHER


## The tier of what recipe `rid` makes (1 for anything that is not a part).
static func _recipe_tier(ship, rid: String) -> int:
	return int(ship.components.def(str(ship.crafting.def(rid)["output"]["item"])).get("tier", 1))


## The recipe of the Repair Drone (R1) when this salvage may also offer to scan its blueprint, else "": it is unknown, and a roll of
## data/drift.json `loot.drone_scan` (a fifth of the wrecks, about as rare as a tier-2 part) comes up. The roll is made from the run's seed and
## the fights won, so a given wreck always offers the same and the campaign's rng stream is left alone.
static func drone_scan(ship, c) -> String:
	var rid := recipe_for(ship, str(CrewMember.config().get("drone", {}).get("item", "")))
	if rid == "" or ship.crafting.is_known(rid):
		return ""
	var roll := RandomNumberGenerator.new()
	roll.seed = hash([c.seed_value, c.fights_won, c.stage])
	return rid if roll.randf() < float(c.cfg["loot"].get("drone_scan", 0.0)) else ""


## The salvage event for `enemy` (its Ship, as the fight left it) after a fight in `state` ("won", "captured" or "spared").
## Returns {} when there is nothing to offer. Rows, in order: "Cut out the X" (the part, to the cargo), at
## most one "Scan the X" (its blueprint: the unknown recipe of an offered part that the ship can craft next, see next_recipe),
## and for a win "Strip her for scrap". A captured ship's scrap was paid already (Campaign.fight_done); a spared ship offers one part and the scan row
## and no strip row (she limps away under her own power).
## A ghost ship (`hollow`: it came from a place the Hollow tide has taken, which is what the campaign says when the
## flag is left out) offers only the strip row, at half the scrap, whatever the state: nothing aboard is worth cutting
## out or scanning, and its scrap was not paid at the fight. `threat` (1-5 skulls, 0 when unknown) adds parts to the
## pick (picks_for) and a line to the page when that gave more rows.
static func event_for(enemy, state: String, c, ship, hollow = null, threat := 0) -> Dictionary:
	var ghost: bool = c.is_hollow(c.current) if hollow == null else bool(hollow)
	if ghost:
		return {} if state == "spared" else _ghost_event(enemy, c)  # a spared ghost gives nothing (Campaign.fight_done)
	var pool := []
	for id in parts(enemy):
		if not pool.has(id):
			pool.append(id)
	var picked := []
	var base := int(PICKS.get(state, PICKS["won"]))
	for i in picks_for(state, threat, c, ship):
		if pool.is_empty():
			break
		picked.append(pool.pop_at(c.rng.randi() % pool.size()))
	picked.sort()
	var choices := []
	for id in picked:
		var nm := _name(ship, id)
		choices.append(_row("Cut out the %s" % nm, "The cutters bite through the mounts and the %s comes free." % nm, {"items": {id: 1}}))
	var offered := {}  # recipe -> the picked part that shows it
	for id in picked:
		var rid := recipe_for(ship, id)
		if rid != "" and not offered.has(rid):
			offered[rid] = id
	var scan_rid := next_recipe(ship, offered.keys())  # the recipe the ship can craft next, not the grandest on the page
	if scan_rid != "":
		var scan: String = offered[scan_rid]
		choices.append(_row("Scan the %s (learn its blueprint)" % _name(ship, scan), "The scanner maps every weld and wire of the %s." % _name(ship, scan), {"blueprint": [scan_rid]}))
	var foe := str(enemy.name) if enemy != null else "ship"
	var text := "Nobody is left standing aboard the %s. Your crew strip her hold, then pick one prize to cut loose." % foe
	var more := DANGEROUS_TEXT if picked.size() > base + TraitSet.loot_bonus(ship) else ""  # the bonus of a crew member is not the threat's
	if state == "spared":
		text = "The %s limps off, but her crew leave one prize on the airlock: your cutters have time for it." % foe
	elif state != "captured":
		var scrap := strip_scrap(enemy, c)
		choices.append(_row("Strip her for scrap (+%d)" % scrap, "You cut her down to the frame. What is left breaks up behind you.", {"items": {"scrap": scrap}}))
		text = "The %s hangs dead, venting. Your cutters have time for one job before she breaks up." % foe
	text += more
	if choices.is_empty():
		return {}
	var drone := drone_scan(ship, c)  # (an extra row on a salvage that exists anyway, before the strip row)
	if drone != "":
		choices.insert(choices.size() - (1 if state == "won" else 0), _row("Scan the service drone bay (learn the Repair Drone blueprint)", "A wrecked service drone still has its plans in its memory. The scanner copies them.", {"blueprint": [drone]}))
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
