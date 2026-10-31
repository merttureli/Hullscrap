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
