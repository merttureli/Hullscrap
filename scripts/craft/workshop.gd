extends RefCounted
## The fabricator's level (its own, upgraded in build mode), and its tools and speed from the powered workshop modules in its room.
## Pure and deterministic, no nodes.

const ARM := "robot_arm"
const CUTTER := "laser_cutter"
const RIG := "assembly_rig"
const FORGE := "nanoforge"
const FAB := "fabricator"
const Rooms = preload("res://scripts/sim/rooms.gd")
const MAX_LEVEL := 4
const SPEED_PER_MODULE := 0.25  ## crafting speed each robot arm or assembly rig in the fabricator's room adds ...
const SPEED_MAX := 0.5  ## ... up to this much


## `ship_components`: a components.gd instance; `rooms_result`: Rooms.compute's result;
## `powered`: uid -> bool from the power solver. Returns {"level": int, "tools": [String],
## "modules": [uid], "speed": float}. A module counts when it is powered and its anchor cell is in the same
## room as the fabricator's anchor cell.
## The level is the fabricator's own (`fab_level` on its instance, 1 to 4, raised in build mode: upgrade()). Tools and
## speed come from the modules in its room: a laser cutter adds the tool "laser_cutter", a nanoforge "nanoforge", and
## each robot arm or assembly rig makes crafting 25% faster, up to +50%.
## An unpowered (or missing) fabricator is level 0: it cannot craft. One outside any room has no tools and no speed bonus.
static func level_of(ship_components, rooms_result: Dictionary, fab_uid: int, powered: Dictionary) -> Dictionary:
	var out := {"level": 0, "tools": [], "modules": [], "speed": 1.0}
	var insts: Dictionary = ship_components.instances
	if not insts.has(fab_uid) or not powered.get(fab_uid, false):
		return out
	out["level"] = clampi(int(insts[fab_uid].get("fab_level", 1)), 1, MAX_LEVEL)
	var room_of: Dictionary = rooms_result["room_of"]
	var room: int = room_of.get(insts[fab_uid]["anchor"], -1)
	if room < 0:
		return out
	var n := _count_modules(ship_components, room_of, room, powered, out["modules"])
	var boosters: int = n[ARM] + n[RIG]
	out["speed"] = 1.0 + minf(SPEED_MAX, SPEED_PER_MODULE * boosters)
	if n[CUTTER] >= 1:
		out["tools"].append(CUTTER)
	if n[FORGE] >= 1:
		out["tools"].append(FORGE)
	return out


## The workshop modules of `room`: {id: count}, the powered ones' uids appended to `uids`.
static func _count_modules(ship_components, room_of: Dictionary, room: int, powered: Dictionary, uids: Array) -> Dictionary:
	var n := {ARM: 0, CUTTER: 0, RIG: 0, FORGE: 0}
	var insts: Dictionary = ship_components.instances
	var keys: Array = insts.keys()
	keys.sort()
	for uid in keys:
		var id: String = insts[uid]["id"]
		if n.has(id) and powered.get(uid, false) and room_of.get(insts[uid]["anchor"], -1) == room:
			n[id] += 1
			uids.append(uid)
	return n


## The level the modules in a fabricator's room gave it before it had a level of its own (an arm: 2; a rig and two arms: 3;
## a nanoforge on top: 4), power ignored. Used once, to give an older save's fabricator the level it already had.
static func legacy_level(ship_components, rooms_result: Dictionary, fab_uid: int) -> int:
	var insts: Dictionary = ship_components.instances
	var room_of: Dictionary = rooms_result["room_of"]
	var room: int = room_of.get(insts[fab_uid]["anchor"], -1)
	if room < 0:
		return 1
	var all := {}
	for uid in insts:
		all[uid] = true
	var n := _count_modules(ship_components, room_of, room, all, [])
	var level := 1
	if n[ARM] >= 1:
		level = 2
	if n[RIG] >= 1 and n[ARM] >= 2:
		level = 3
		if n[FORGE] >= 1:
			level = 4
	return level


## Give the fabricators `components.legacy_fabs` (read from a save with no level) the level their modules made. Call after the
## grid is loaded; saved from then on.
static func migrate(ship) -> void:
	var comps = ship.components
	if comps.legacy_fabs.is_empty():
		return
	var rooms := Rooms.compute(ship.grid)
	for uid in comps.legacy_fabs:
		if comps.instances.has(uid):
			comps.instances[uid]["fab_level"] = legacy_level(comps, rooms, uid)
	comps.legacy_fabs.clear()


## The ship's fabricator uid, or -1.
static func fab_uid(ship) -> int:
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		if ship.components.instances[uid]["id"] == FAB:
			return uid
	return -1


## The cost of fabricator level `level` ({} for 1 or beyond the top): data/components.json, the fabricator's `upgrades`.
static func upgrade_cost(ship, level: int) -> Dictionary:
	var up: Dictionary = ship.components.def(FAB).get("upgrades", {})
	var out := {}
	for m in up.get(str(level), {}):
		out[str(m)] = int(up[str(level)][m])
	return out


## What the upgrade card says about fabricator `uid`: {level, next (0 at the top), cost, short ({material: missing}),
## new (known blueprints the next level opens), total (known blueprints the fabricator can make at the next level),
## text, can}.
static func upgrade_info(ship, uid: int) -> Dictionary:
	var level := clampi(int(ship.components.instances[uid].get("fab_level", 1)), 1, MAX_LEVEL)
	var out := {"level": level, "next": 0, "cost": {}, "short": {}, "new": 0, "total": 0, "text": "Fully upgraded", "can": false}
	if level >= MAX_LEVEL:
		return out
	var nxt := level + 1
	out["next"] = nxt
	out["cost"] = upgrade_cost(ship, nxt)
	out["short"] = ship.inventory.missing(out["cost"])
	for id in ship.crafting.known:
		var r: Dictionary = ship.crafting.def(id)
		if str(r["station"]) != "fabricator" or int(r["fab_level"]) > nxt:
			continue
		out["total"] += 1
		if int(r["fab_level"]) == nxt:
			out["new"] += 1
	out["text"] = "Level %d: %d more blueprint%s can be made (%d in all)" % [nxt, out["new"], "" if out["new"] == 1 else "s", out["total"]]
	out["can"] = out["short"].is_empty()
	return out


## Pay for and apply the next level of fabricator `uid`. Returns "" or why not.
static func upgrade(ship, uid: int) -> String:
	if not ship.components.instances.has(uid) or ship.components.instances[uid]["id"] != FAB:
		return "not a fabricator"
	var inf := upgrade_info(ship, uid)
	if int(inf["next"]) == 0:
		return "Fully upgraded"
	if not inf["can"]:
		return "Not enough materials for level %d" % inf["next"]
	ship.inventory.spend(inf["cost"])
	ship.components.instances[uid]["fab_level"] = inf["next"]
	ship.log_event("Fabricator upgraded to level %d" % inf["next"])
	return ""


## The ship's best fabricator: level_of() for each placed one, the highest level wins (then the most
## tools, then the lowest uid). {"level", "tools", "modules", "uid", "count"}: level 0 and uid -1 when
## no fabricator is powered, `count` is how many fabricators the ship has. Reads the ship's own rooms
## and power (refreshing it first).
static func best(ship) -> Dictionary:
	ship.refresh()
	var out := {"level": 0, "tools": [], "modules": [], "uid": -1, "count": 0, "speed": 1.0}
	var rooms := {"room_of": ship.atmosphere.room_of}
	var powered: Dictionary = ship.power_state.get("powered", {})
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		if ship.components.instances[uid]["id"] != FAB:
			continue
		out["count"] += 1
		var r := level_of(ship.components, rooms, uid, powered)
		if r["level"] > out["level"] or (r["level"] == out["level"] and r["level"] > 0 and r["tools"].size() > out["tools"].size()):
			var count: int = out["count"]
			out = r
			out["uid"] = uid
			out["count"] = count
	return out
