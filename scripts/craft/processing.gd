extends RefCounted
## The ship's smelters (docs/CONTENT.md section 12): the processing station that turns scrap and ores into
## steel, alloy, conductors and glass lattice. Like workshop.gd for the fabricator, it reads the powered parts of
## the `smelter` family and says what the station can do: {station, level, tools, speed, uid, count, manned, ...}.
## crafting.gd keeps the smelter's queue and runs it with this result (ShipSim._smelt); jobs.gd asks post_wanted()
## so crew man a smelter only while it has something to smelt. Pure and deterministic, no nodes.
## A smelter part's stats: smelt_level (what it may smelt: a recipe's fab_level), smelt_speed (1 = a recipe's own
## seconds; the line's output multiplies it, stats.gd), plasma (1: it is a Plasma Forge, the tool "plasma").
## The ship's smelters share one queue. Its level is its best powered smelter's, its tools are all the powered ones
## together, and the fastest one (the lead) sets the speed and is the post a crew member mans: manned, it works
## faster by data/crew.json manned.process_speed (30%) times the operator's manned factor.

const Crafting = preload("res://scripts/craft/crafting.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")

const SMELTER := "smelter"
const CHAIN: Array[String] = ["smelter_scrap_mk1", "smelter_mk1", "smelter_mk2", "smelter_mk3"]  ## the upgrade path: each swaps for the next (the Plasma Forge is a separate part, built by hand)
const PLASMA := "plasma"  ## the tool a Plasma Forge provides (a recipe lists it in `tools`)


## The smelter station of `ship`: {"station", "level" (0 = none powered), "tools", "speed" (work per second,
## 0 = none), "base_speed" (without a crew member), "manned" (the lead is manned), "uid" (the lead, -1 = none),
## "count" (smelters on the ship), "parts" (the powered ones' uids)}. Refreshes the ship first.
static func best(ship, station := SMELTER) -> Dictionary:
	ship.refresh()
	var out := {"station": station, "level": 0, "tools": [], "speed": 0.0, "base_speed": 0.0, "manned": false, "uid": -1, "count": 0, "parts": []}
	var powered: Dictionary = ship.power_state.get("powered", {})
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		if str(ship.components.def(inst["id"]).get("family", "")) != station:
			continue
		out["count"] += 1
		if not powered.get(uid, false):
			continue
		var st: Dictionary = ship.effective(inst["id"])["stats"]
		out["parts"].append(uid)
		out["level"] = maxi(int(out["level"]), int(st.get("smelt_level", 1)))
		if float(st.get(PLASMA, 0.0)) > 0.0 and not out["tools"].has(PLASMA):
			out["tools"].append(PLASMA)
		var speed := float(st.get("smelt_speed", 1.0))
		if speed > float(out["base_speed"]):  # the fastest leads; the lowest uid on a tie
			out["base_speed"] = speed
			out["uid"] = uid
	if out["uid"] >= 0:
		var bonus := manned_bonus(ship, out["uid"])
		out["manned"] = bonus > 0.0
		out["speed"] = float(out["base_speed"]) * (1.0 + bonus)
	return out


## The extra speed (a fraction, 0.3 = 30% faster) the crew member manning part `uid` gives it: 0 with nobody there.
static func manned_bonus(ship, uid: int) -> float:
	if TraitSet.operator_of(ship, uid) == null:
		return 0.0
	return manned_speed() * TraitSet.manned_factor(ship, uid)


## What an average operator adds to a smelter's speed (data/crew.json manned.process_speed): 0.3.
static func manned_speed() -> float:
	return float(CrewMember.config().get("manned", {}).get("process_speed", 0.0))


## Should a crew member man part `uid` now (jobs.gd build_board)? Every post but a smelter's: yes. A smelter is
## manned only while it leads a queue that has work, so nobody waits at an idle one.
static func post_wanted(ship, uid: int) -> bool:
	var station := str(ship.components.def(ship.components.instances[uid]["id"]).get("family", ""))
	if station == Crafting.FABRICATOR or not Crafting.STATIONS.has(station):
		return true
	return int(ship.crafting.lead.get(station, -1)) == uid and not ship.crafting.queue_of(station).is_empty()


## The smelter an Upgrade button works on: the weakest of the chain's installed parts (the lowest uid on a tie), or -1.
static func upgrade_uid(ship) -> int:
	var best := -1
	var rank := 99
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var at := CHAIN.find(str(ship.components.instances[uid]["id"]))
		if at >= 0 and at < rank:
			best = uid
			rank = at
	return best


## Where the next smelter would go to replace `uid`: {"anchor" (Vector2i, or null), "sides" (the sides on which clearing parts would make
## room: "right", "left", "above", "below")}. A spot must cover the old part's cells, keep its rotation, and have only floor, inside the hull,
## with no other part or wreckage (the old part's own cells are free).
static func swap_spot(ship, uid: int, next_id: String) -> Dictionary:
	var inst: Dictionary = ship.components.instances[uid]
	var rot := int(inst["rot"])
	var old: Array = inst["cells"]
	var lo: Vector2i = old[0]
	var hi: Vector2i = old[0]
	for c in old:
		lo = lo.min(c)
		hi = hi.max(c)
	var size: Array = ship.components.def(next_id)["size"]
	var swap := posmod(rot, 2) == 1
	var w := int(size[1 if swap else 0])
	var h := int(size[0 if swap else 1])
	var out := {"anchor": null, "sides": []}
	var comps = ship.components
	for dy in range(0, h - (hi.y - lo.y + 1) + 1):
		for dx in range(0, w - (hi.x - lo.x + 1) + 1):
			var anchor := lo - Vector2i(dx, dy)  # (the old part sits dx, dy cells inside the new footprint: it grows right and down first)
			var free := true
			var blocked_by_parts := true
			for c in comps.footprint(next_id, anchor, rot):
				if not ship.grid.in_hull(c):
					free = false
					blocked_by_parts = false
				elif comps.at(c) != uid and not comps.free_floor(ship.grid, c):
					free = false
					if comps.any_at(c) < 0 and comps.wreck_at(c) < 0:
						blocked_by_parts = false  # (not floor: a wall or space, clearing parts does not help)
			if free and out["anchor"] == null:
				out["anchor"] = anchor
			elif not free and blocked_by_parts:
				var nlo := anchor
				var nhi := anchor + Vector2i(w - 1, h - 1)
				for side in [["right", nhi.x > hi.x], ["left", nlo.x < lo.x], ["below", nhi.y > hi.y], ["above", nlo.y < lo.y]]:
					if side[1] and not out["sides"].has(side[0]):
						out["sides"].append(side[0])
	return out


## What the smelter Upgrade button says about smelter `uid`: {"next" (the next part's id, "" at the top or off the chain), "name", "text" (the next
## part and what it adds), "cost", "short", "why" ("" when it can go ahead, else the reason), "can", "anchor"}.
static func upgrade_info(ship, uid: int) -> Dictionary:
	var out := {"next": "", "name": "", "text": "", "cost": {}, "short": {}, "why": "", "can": false, "anchor": null}
	var at := CHAIN.find(str(ship.components.instances[uid]["id"])) if ship.components.instances.has(uid) else -1
	if at < 0:
		return out
	if at == CHAIN.size() - 1:
		out["text"] = "Fully upgraded"
		return out
	var nid: String = CHAIN[at + 1]
	var cur: Dictionary = ship.effective(CHAIN[at])["stats"]
	var nxt: Dictionary = ship.effective(nid)["stats"]
	out["next"] = nid
	out["name"] = str(ship.components.def(nid).get("name", nid))
	out["text"] = "%s: smelt level %d, speed x%s (now level %d, x%s)" % [out["name"], int(nxt.get("smelt_level", 1)), str(snappedf(float(nxt.get("smelt_speed", 1.0)), 0.01)), int(cur.get("smelt_level", 1)), str(snappedf(float(cur.get("smelt_speed", 1.0)), 0.01))]
	var c = ship.crafting
	if not c.has(nid) or not c.is_known(nid):
		out["why"] = "Blueprint not found yet"
		return out
	var rec: Dictionary = c.def(nid)
	out["cost"] = rec["materials"].duplicate()
	out["short"] = ship.inventory.missing(rec["materials"])
	var fab: Dictionary = preload("res://scripts/craft/workshop.gd").best(ship)
	var why: String = c.can_craft(nid, ship.inventory, fab)
	if why.begins_with("missing:"):
		why = ""  # (the cargo is checked below, after the room)
	elif why != "":
		why = why.substr(0, 1).to_upper() + why.substr(1)
		out["why"] = why
		return out
	var spot := swap_spot(ship, uid, nid)
	out["anchor"] = spot["anchor"]
	if spot["anchor"] == null:
		out["why"] = "Needs one more free column of floor beside it"
		if not spot["sides"].is_empty():
			out["text"] += ". Clear the floor on its %s" % " or ".join(spot["sides"])
		return out
	if not out["short"].is_empty():
		var parts := PackedStringArray()
		for m in out["short"]:
			parts.append("%d %s" % [out["short"][m], c.name_of(m).to_lower()])
		out["why"] = "Short: " + ", ".join(parts)
		return out
	out["can"] = true
	return out


## Pay for the next smelter and swap it in for `uid`, in the same room, rotation and place (the old part goes to the cargo; cables, the
## queue and the room stay). Returns "" or why not.
static func upgrade(ship, uid: int) -> String:
	if not ship.components.instances.has(uid):
		return "no smelter"
	var inf := upgrade_info(ship, uid)
	if str(inf["next"]) == "":
		return "Fully upgraded" if CHAIN.has(str(ship.components.instances[uid]["id"])) else "Not on the upgrade path"
	if not inf["can"]:
		return str(inf["why"])
	var old_id := str(ship.components.instances[uid]["id"])
	var rot := int(ship.components.instances[uid]["rot"])
	var old_anchor: Vector2i = ship.components.instances[uid]["anchor"]
	ship.components.remove_uid(uid)
	var nu: int = ship.components.place(ship.grid, str(inf["next"]), inf["anchor"], rot)
	if nu < 0:  # (cannot happen: the spot was checked) put the old one back
		ship.components.place(ship.grid, old_id, old_anchor, rot)
		return "No room"
	ship.inventory.spend(inf["cost"])
	ship.inventory.add(old_id, 1)
	ship.log_event("%s upgraded to %s" % [ship.components.def(old_id).get("name", old_id), inf["name"]])
	ship.mark_dirty()
	return ""
