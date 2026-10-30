extends RefCounted
## The fabricator's level and tools, from the powered workshop modules in its room.
## Pure and deterministic, no nodes.

const ARM := "robot_arm"
const CUTTER := "laser_cutter"
const RIG := "assembly_rig"
const FORGE := "nanoforge"


## `ship_components`: a components.gd instance; `rooms_result`: Rooms.compute's result;
## `powered`: uid -> bool from the power solver. Returns {"level": int, "tools": [String],
## "modules": [uid]}. A module counts when it is powered and its anchor cell is in the same
## room as the fabricator's anchor cell.
## Level 1 is the base; one robot arm makes 2; an assembly rig plus two arms make 3; a nanoforge
## on top of that makes 4. A laser cutter adds the tool "laser_cutter", a nanoforge "nanoforge".
## An unpowered (or missing) fabricator is level 0: it cannot craft. One outside any room is
## level 1 with no tools.
static func level_of(ship_components, rooms_result: Dictionary, fab_uid: int, powered: Dictionary) -> Dictionary:
	var out := {"level": 0, "tools": [], "modules": []}
	var insts: Dictionary = ship_components.instances
	if not insts.has(fab_uid) or not powered.get(fab_uid, false):
		return out
	out["level"] = 1
	var room_of: Dictionary = rooms_result["room_of"]
	var room: int = room_of.get(insts[fab_uid]["anchor"], -1)
	if room < 0:
		return out
	var n := {ARM: 0, CUTTER: 0, RIG: 0, FORGE: 0}
	var uids: Array = insts.keys()
	uids.sort()
	for uid in uids:
		var id: String = insts[uid]["id"]
		if n.has(id) and powered.get(uid, false) and room_of.get(insts[uid]["anchor"], -1) == room:
			n[id] += 1
			out["modules"].append(uid)
	var level := 1
	if n[ARM] >= 1:
		level = 2
	if n[RIG] >= 1 and n[ARM] >= 2:
		level = 3
		if n[FORGE] >= 1:
			level = 4
	out["level"] = level
	if n[CUTTER] >= 1:
		out["tools"].append(CUTTER)
	if n[FORGE] >= 1:
		out["tools"].append(FORGE)
	return out
