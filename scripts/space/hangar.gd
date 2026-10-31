extends RefCounted
## The hangar's list (docs/CONTENT.md section 19): the ships a new run can start with. A starter is any ship design
## (data/ships and the ships/ of every pack, through the content loader) with a `hangar` field {group, layout, unlock}:
## group is the tab (a race or a faction), layout is A, B or C (the race's signature, a different strategy, the odd
## one), unlock is the id of an unlock (unlocks.gd) or "" for a ship that is open from the start. The first three
## starters get theirs from data/hangar.json, because tests/tool_make_starters.gd rewrites their files. An unlock of
## kind starter_ship whose payload names the design also locks it. Whether a ship is open is the profile's say
## (profile.gd). No nodes, no drawing.

const Content = preload("res://scripts/data/content.gd")
const Unlocks = preload("res://scripts/space/unlocks.gd")

const LAYOUTS: Array[String] = ["A", "B", "C"]
const LOCKED_HINT := "Locked."


## Every starter, by group, layout and name: {id, name, path, pack, group, layout, unlock, blurb, crew [{name, species}]}.
static func starters() -> Array:
	var defaults := _defaults()
	var out := []
	for s in Content.ships():
		var design: Dictionary = s["design"]
		var h = design.get("hangar", defaults.get(s["id"]))
		if not h is Dictionary:
			continue  # an enemy or a design that is not a starter
		var id := str(s["id"])
		var unlock := str(h.get("unlock", ""))
		var crew := []
		for m in design.get("crew", []) if design.get("crew") is Array else []:
			if m is Dictionary:
				crew.append({"name": str(m.get("name", "")), "species": str(m.get("species", "human"))})
		out.append({"id": id, "name": str(design.get("name", id)), "path": str(s["path"]), "pack": str(s["pack"]), "group": str(h.get("group", "")),
			"layout": str(h.get("layout", "A")), "unlock": unlock if unlock != "" else Unlocks.for_ship(id), "blurb": str(design.get("blurb", "")), "crew": crew})
	out.sort_custom(func(a, b): return [a["group"], a["layout"], a["name"]] < [b["group"], b["layout"], b["name"]])
	return out


static func _defaults() -> Dictionary:
	var path: String = Content.root + "/hangar.json"
	var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return d["ships"] if d is Dictionary and d.get("ships") is Dictionary else {}


## Is `entry` (from starters) still locked for `profile` (profile.gd; null = nothing earned)?
static func locked(entry: Dictionary, profile) -> bool:
	var unlock := str(entry.get("unlock", ""))
	return unlock != "" and (profile == null or not profile.has_unlock(unlock))


## What to tell the player about a locked `entry`: how its unlock is earned.
static func hint(entry: Dictionary) -> String:
	var how := Unlocks.how_of(str(entry.get("unlock", "")))
	return how if how != "" else LOCKED_HINT


## The group tabs of `list`, in order of the list.
static func groups(list: Array) -> Array:
	var out := []
	for e in list:
		if not out.has(e["group"]):
			out.append(e["group"])
	return out


## The index in `list` of the ship of `group` with `layout`, -1 when there is none.
static func find(list: Array, group: String, layout: String) -> int:
	for i in list.size():
		if list[i]["group"] == group and list[i]["layout"] == layout:
			return i
	return -1


## How many ships of `group` are open for `profile`: [open, all].
static func open_count(list: Array, group: String, profile) -> Array:
	var n := 0
	var all := 0
	for e in list:
		if e["group"] == group:
			all += 1
			n += int(not locked(e, profile))
	return [n, all]


## Every problem in the list, one message each. Empty when it is sound: a ship has a group and a layout, no two share
## a group and a layout, its unlock exists, and every entry of data/hangar.json names a design.
static func validate() -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for e in starters():
		var at := "%s: starter '%s'" % [e["path"], e["id"]]
		if e["group"] == "":
			out.append(at + ": hangar.group must be a non-empty string")
		if not LAYOUTS.has(e["layout"]):
			out.append("%s: hangar.layout must be one of %s (got '%s')" % [at, ", ".join(LAYOUTS), e["layout"]])
		var key: String = e["group"] + "/" + e["layout"]
		if seen.has(key):
			out.append("%s: group '%s' already has a layout %s (%s)" % [at, e["group"], e["layout"], seen[key]])
		seen[key] = e["id"]
		if e["unlock"] != "" and not Unlocks.has(e["unlock"]):
			out.append("%s: hangar.unlock '%s' is not in unlocks.json" % [at, e["unlock"]])
	for id in _defaults():
		if not Content.has("ships", str(id)):
			out.append("%s/hangar.json: '%s' is not a ship design" % [Content.root, id])
	return out
