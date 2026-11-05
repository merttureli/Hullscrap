extends "res://tests/base_test.gd"
## Ship save version 7 (playtest 2, P2): the tier 1-2 weapons, engines, reactors and shields took less room inside, so a save made
## before it holds those parts at their old size. scripts/ship/migrate_parts.gd re-anchors them when Ship.load_dict meets a save
## below version 7, and keeps the power (and the belts) reaching them; tests/tool_migrate_parts.gd moved the shipped designs.

const Wall = preload("res://tests/fixture_wall.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Components = preload("res://scripts/ship/components.gd")
const MigrateParts = preload("res://scripts/ship/migrate_parts.gd")
const HullOutline = preload("res://scripts/ship/hull_outline.gd")

const THICK := 1


func _comps() -> Components:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	return c


## An old (version 6) save of a laser through a wall, a reactor and a helm, wired the way it was when parts were bigger: the laser
## was 4x2 (x 13..16) with a cable at its right-hand end, the reactor 4x4 (x 17..20) with a cable out of its right-hand side to a helm.
## Built from a new-geometry ship whose anchors and cables are then put back to the old ones. Returns the save.
func _old_save() -> Dictionary:
	var ship := Wall.wall_ship(THICK, 0)
	check(ship.components.place_mount(ship.grid, "laser_mk1", Wall.out_anchor(0), 0) >= 0, "(setup: the laser)")
	check(ship.components.place(ship.grid, "reactor_mk1", Vector2i(17, 16), 0) >= 0, "(setup: the reactor)")
	check(ship.components.place(ship.grid, "helm", Vector2i(21, 16), 0) >= 0, "(setup: the helm)")
	var d := ship.to_dict()
	d["version"] = 6
	for inst in d["components"]["instances"]:
		if inst["id"] == "laser_mk1":
			inst["anchor"] = [13, 16]  # the old 4x2 inside half: x 13..16, y 16..17
	var cells := [[16, 17], [17, 17], [20, 17], [21, 17]]  # the old laser's last column (x 16) to the reactor; the old reactor's last column (x 20) to the helm
	d["cables"] = {"version": 1, "cells": cells}
	return d


func test_an_old_save_loads_with_its_parts_moved_and_everything_still_powered() -> void:
	var d := _old_save()
	var ship := Wall.wall_ship(THICK, 0)
	eq(ship.load_dict(d), "", "loads")
	var laser := -1
	for uid in ship.components.instances:
		if ship.components.instances[uid]["id"] == "laser_mk1":
			laser = uid
	var inst: Dictionary = ship.components.instances[laser]
	eq(inst["anchor"], Vector2i(14, 16), "the laser's 2x2 breech is centred behind its barrel (x 14..15)")
	eq(inst["out_anchor"], Wall.out_anchor(0), "the barrel has not moved")
	eq(inst["cells"].size(), 4, "a 2x2 inside half")
	check(ship.components.has_outside(laser) and ship.components.link_intact(ship.grid, laser), "still mounted through the wall")
	for uid in ship.components.instances:
		check(ship.power_state["powered"].get(uid, false), "%s is powered" % ship.components.instances[uid]["id"])
	check(ship.cables.has(Vector2i(15, 17)), "the cable was carried on into the laser's new cells")
	check(ship.cables.has(Vector2i(19, 17)) and ship.cables.has(Vector2i(18, 17)), "and into the reactor's new cells (x 17..18)")
	eq(ship.to_dict()["version"], 7, "and it saves as version 7")


func test_a_version_7_save_is_not_touched() -> void:
	var d := _old_save()
	d["version"] = 7
	var ship := Wall.wall_ship(THICK, 0)
	eq(ship.load_dict(d), "", "loads")
	for uid in ship.components.instances:
		if ship.components.instances[uid]["id"] == "laser_mk1":
			eq(ship.components.instances[uid]["anchor"], Vector2i(13, 16), "a version 7 save is not re-anchored (the loader mounts the bare part again from where it stands)")


func test_every_resized_mount_is_re_anchored_to_the_centre_at_all_four_rotations() -> void:
	var comps := _comps()
	for rot in 4:
		for id in ["laser_mk1", "engine_mk1", "pulse_mk2", "longburn_mk2"]:
			var old_anchor := Wall.corner(rot, -2, 1, THICK, THICK + 1)  # the old 4x2 inside half, behind the wall
			var out := Wall.out_anchor(rot, comps.def(id)["mount"]["outside"][1])
			var d := {"version": 6, "components": {"version": 4, "next_uid": 2, "instances": [{"uid": 1, "id": id, "anchor": [old_anchor.x, old_anchor.y], "rot": rot, "out": [out.x, out.y]}]}}
			var m := MigrateParts.migrate(d, comps.by_id)
			var a: Array = m["components"]["instances"][0]["anchor"]
			eq(Vector2i(int(a[0]), int(a[1])), Wall.corner(rot, -1, 0, THICK, THICK + 1), "%s at rot %d: the 2x2 breech is the middle of the old 4x2" % [id, rot])
			eq(d["components"]["instances"][0]["anchor"], [old_anchor.x, old_anchor.y], "the save it was given is left as it was")


func test_a_part_that_did_not_shrink_or_is_unknown_is_left_alone() -> void:
	var comps := _comps()
	var inst := [{"uid": 1, "id": "afterburner", "anchor": [10, 10], "rot": 0}, {"uid": 2, "id": "helm", "anchor": [14, 10], "rot": 0},
		{"uid": 3, "id": "engine_mk3", "anchor": [18, 10], "rot": 0}, {"uid": 4, "id": "no_such_part", "anchor": [1, 1], "rot": 0}]
	var m := MigrateParts.migrate({"version": 6, "components": {"instances": inst}}, comps.by_id)
	eq(m["components"]["instances"].map(func(i): return i["anchor"]), [[10, 10], [14, 10], [18, 10], [1, 1]], "a unique part, a helm, a tier 3 engine and an unknown id")
	eq(MigrateParts.migrate({"version": 2}, comps.by_id), {"version": 2}, "an old save with no parts")
	eq(MigrateParts.migrate({"version": 6, "components": {"instances": [5, {"id": "laser_mk1"}]}}, comps.by_id)["components"]["instances"], [5, {"id": "laser_mk1"}], "garbage is passed on for the loader to refuse")


func test_a_reactor_or_a_shield_keeps_its_top_left_and_the_cables_in_the_lost_columns_are_joined_on() -> void:
	var comps := _comps()
	for id in ["reactor_mk1", "shield_mk2", "kett_hive_battery"]:
		for rot in [0, 1]:
			var d := {"version": 6, "components": {"instances": [{"uid": 1, "id": id, "anchor": [10, 10], "rot": rot}]}, "cables": {"version": 1, "cells": [[13, 11], [13, 13]] if rot == 0 else [[11, 13]]}}
			var m := MigrateParts.migrate(d, comps.by_id)
			eq(m["components"]["instances"][0]["anchor"], [10, 10], "%s rot %d keeps its top-left" % [id, rot])
			var now := Rect2i(Vector2i(10, 10), Vector2i(2, 4) if rot == 0 else Vector2i(4, 2))
			var cells := {}
			for p in m["cables"]["cells"]:
				cells[Vector2i(int(p[0]), int(p[1]))] = true
			for p in d["cables"]["cells"]:
				check(cells.has(Vector2i(int(p[0]), int(p[1]))), "%s rot %d: the old cable cell %s is still there" % [id, rot, str(p)])
			var touching := false
			for c in cells:
				if now.has_point(c):
					touching = true
			check(touching, "%s rot %d: a cable lies on the new footprint, so the network still reaches it" % [id, rot])
			for c in cells:  # only cells inside the old footprint were added
				if not d["cables"]["cells"].any(func(p): return Vector2i(int(p[0]), int(p[1])) == c):
					check(Rect2i(Vector2i(10, 10), Vector2i(4, 4)).has_point(c), "%s: the added cable %s is under the old footprint" % [id, str(c)])


func test_a_belt_beside_the_old_footprint_is_carried_on_to_touch_the_new_one() -> void:
	var comps := _comps()
	var d := {"version": 6, "components": {"instances": [{"uid": 1, "id": "laser_mk1", "anchor": [13, 16], "rot": 0, "out": [13, 13]}]},
		"belts": {"version": 1, "cells": [[17, 16], [18, 16]], "cut": []}}
	var m := MigrateParts.migrate(d, comps.by_id)
	var cells := {}
	for p in m["belts"]["cells"]:
		cells[Vector2i(int(p[0]), int(p[1]))] = true
	check(cells.has(Vector2i(16, 16)), "the belt runs on across the cell the laser gave up")
	check(not cells.has(Vector2i(15, 16)) and not cells.has(Vector2i(14, 16)), "and stops short of the laser's new cells (belts never lie under a system)")
	check(cells.has(Vector2i(17, 16)) and cells.has(Vector2i(18, 16)), "the belt that was there stays")


## Every design file: data/ships/*.json and the ships/ folder of each pack.
func _designs() -> Array[String]:
	var out: Array[String] = []
	_add(out, "res://data/ships/")
	for p in DirAccess.get_directories_at("res://data/packs"):
		_add(out, "res://data/packs/%s/ships/" % p)
	return out


func _add(out: Array[String], dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				out.append(dir + f)


func test_every_shipped_design_is_on_version_7_with_all_its_parts_powered_and_its_floor_reachable() -> void:
	var paths := _designs()
	check(paths.size() >= 32, "the designs were found (%d)" % paths.size())
	for path in paths:
		var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
		eq(int(raw["version"]), Ship.VERSION, path.get_file() + ": saved as the current version")
		var ship = Ship.from_design(path)
		check(ship != null, path.get_file() + ": loads")
		if ship == null:
			continue
		for uid in ship.components.instances:
			var inst: Dictionary = ship.components.instances[uid]
			if not ship.build_first:  # (the Blank frame's seed helm has no reactor: the player builds it)
				check(ship.power_state["powered"].get(uid, false), "%s: %s is powered" % [path.get_file(), inst["id"]])
			if ship.components.is_mount(inst["id"]):
				check(ship.components.has_outside(uid) and ship.components.link_intact(ship.grid, uid), "%s: %s is mounted through its wall" % [path.get_file(), inst["id"]])
		var lost := HullOutline.pockets(ship)
		eq(lost.size(), 0, "%s: every floor cell is reachable from the helm by a 2x2 body (%s)" % [path.get_file(), str(lost.slice(0, 4))])
