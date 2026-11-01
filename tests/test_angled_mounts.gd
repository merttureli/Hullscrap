extends "res://tests/base_test.gd"
## Mounts on a sloped hull face (docs/waves/playtest_2.md, G1): the outside half lies against a straight run of
## 45 degree or 1:2 slope cells and faces its normal, the inside half stays on the grid; engines push and guns aim
## along the true direction; the angle survives a save. Straight mounts are in test_mounts.gd.

const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Components = preload("res://scripts/ship/components.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Flight = preload("res://scripts/sim/flight.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Damage = preload("res://scripts/combat/damage.gd")
const Collisions = preload("res://scripts/combat/collisions.gd")

## The face angle of slope45 turned r quarter turns, and of slope2 by (rot, mirror), with the piece-to-piece step along the face.
const SLOPE2 := {[0, false]: [333.434949, Vector2i(2, -1)], [0, true]: [26.565051, Vector2i(2, 1)], [1, false]: [63.434949, Vector2i(1, 2)],
	[1, true]: [116.565051, Vector2i(-1, 2)], [2, false]: [153.434949, Vector2i(-2, 1)], [2, true]: [206.565051, Vector2i(-2, -1)],
	[3, false]: [243.434949, Vector2i(-1, -2)], [3, true]: [296.565051, Vector2i(1, -2)]}
const SLOPE45 := [[45.0, Vector2i(1, 1)], [135.0, Vector2i(-1, 1)], [225.0, Vector2i(-1, -1)], [315.0, Vector2i(1, -1)]]


## A 31x31 ship whose hull has one straight sloped face of `n` pieces (`piece` turned `rot`, mirrored or not) with free floor
## behind it. Returns {ship, grid, angle, mid (the middle of the face), t, nrm, cells (the piece cells in order), len (one piece)}.
func _slope_ship(piece: String, rot: int, mirror := false, n := 4) -> Dictionary:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	var ship := Ship.new("Slope", g)
	ship.inventory.load_dict({"scrap": 800, "copper": 40})
	var angle: float = SLOPE45[rot][0] if piece == "slope45" else SLOPE2[[rot, mirror]][0]
	var step: Vector2i = SLOPE45[rot][1] if piece == "slope45" else SLOPE2[[rot, mirror]][1]
	var len := sqrt(2.0) if piece == "slope45" else sqrt(5.0)
	var t := Vector2.RIGHT.rotated(deg_to_rad(angle))
	var nrm := Vector2.UP.rotated(deg_to_rad(angle))
	var a0 := Vector2i(15, 15) - step * (n / 2)
	var cells := []
	var first := Vector2.ZERO
	for i in n:
		var anchor := a0 + step * i
		var pc := Shapes.piece_cells(piece, anchor, rot, mirror)
		var lo := Vector2i(999, 999)
		var hi := Vector2i(-999, -999)
		for e in pc:
			g.force_tile(e["cell"], "wall", {"shape": e["shape"], "rot": e["rot"], "mirror": e["mirror"]})
			cells.append(e["cell"])
			lo = lo.min(e["cell"])
			hi = hi.max(e["cell"])
		if i == 0:
			first = Vector2(lo + hi + Vector2i.ONE) / 2.0  # the face runs through the middle of a piece's box
	for y in 31:
		for x in 31:
			var d := Vector2(x + 0.5, y + 0.5) - first
			if d.dot(nrm) < -0.6 and d.dot(nrm) > -9.0 and d.dot(t) > -len / 2.0 and d.dot(t) < (n - 0.5) * len:
				g.force_tile(Vector2i(x, y), "floor")
	return {"ship": ship, "grid": g, "angle": angle, "t": t, "nrm": nrm, "cells": cells, "len": len, "mid": first + t * len * (n - 1) / 2.0}


## The plan for `id` with the pointer `off` cells out from the middle of the face of `s` (and `along` cells along it).
func _plan(s: Dictionary, id := "laser_mk1", off := 1.5, along := 0.0) -> Dictionary:
	var p: Vector2 = s["mid"] + s["nrm"] * off + s["t"] * along
	return s["ship"].components.plan_mount_at(s["grid"], id, Vector2i(int(floor(p.x)), int(floor(p.y))), 0, p)


func test_a_mount_on_a_45_degree_face_takes_its_angle_in_every_quadrant() -> void:
	for rot in 4:
		var s := _slope_ship("slope45", rot)
		var plan := _plan(s)
		eq(plan["why"], "", "slope45 turned %d: the laser fits" % rot)
		near_deg(float(plan.get("angle", -1.0)), 45.0 + 90.0 * rot, "slope45 turned %d: the outside half faces its normal" % rot)
		var uid: int = s["ship"].components.place_planned("laser_mk1", plan)
		check(uid >= 0, "slope45 turned %d: placed" % rot)
		var inst: Dictionary = s["ship"].components.instances[uid]
		check(Mounts.is_angled(inst), "slope45 turned %d: it is an angled mount" % rot)
		near_deg(float(inst["angle"]), 45.0 + 90.0 * rot, "slope45 turned %d: the instance keeps the angle" % rot)
		check(not inst["out_cells"].is_empty(), "slope45 turned %d: the outside half holds cells in space" % rot)
		for c in inst["out_cells"]:
			eq(s["grid"].get_tile(c), "", "slope45 turned %d: the outside half's cell %s is empty space" % [rot, str(c)])


func test_a_mount_on_a_1_to_2_slope_takes_its_angle_in_every_quadrant() -> void:
	for key in SLOPE2:
		var s := _slope_ship("slope2", key[0], key[1])
		var plan := _plan(s)
		eq(plan["why"], "", "slope2 %s: the laser fits" % str(key))
		near_deg(float(plan.get("angle", -1.0)), SLOPE2[key][0], "slope2 %s: the outside half faces the slope's normal" % str(key))
		check(s["ship"].components.place_planned("laser_mk1", plan) >= 0, "slope2 %s: placed" % str(key))


func test_the_inside_half_is_flush_with_the_grid_centred_behind_the_barrel() -> void:
	for case in [["slope45", 0, false], ["slope45", 2, false], ["slope2", 0, false], ["slope2", 1, false], ["slope2", 3, true]]:
		var s := _slope_ship(case[0], case[1], case[2], 5)
		var plan := _plan(s)
		eq(plan["why"], "", "%s: fits" % str(case))
		var uid: int = s["ship"].components.place_planned("laser_mk1", plan)
		var inst: Dictionary = s["ship"].components.instances[uid]
		check(absf(wrapf(float(inst["angle"]) - inst["rot"] * 90.0, -180.0, 180.0)) <= 45.01, "%s: rot is the nearest quarter turn to the angle" % str(case))
		eq(inst["cells"].size(), 4, "%s: the 2x2 breech is whole grid cells" % str(case))
		for c in inst["cells"]:
			eq(s["grid"].get_tile(c), "floor", "%s: the breech is on floor" % str(case))
		var lo := Vector2(inst["cells"][0])
		var mid := lo + Vector2.ONE  # the middle of the 2x2 block
		var line_at: Vector2 = Vector2(inst["out_at"])
		var off := (mid - line_at)
		var across := absf(off.dot(Mounts.along_of(float(inst["angle"]))))
		check(across <= 1.3, "%s: the breech sits behind the barrel (%.2f cells off its middle line)" % [str(case), across])
		check(not inst["link"].is_empty(), "%s: the link is the sloped wall" % str(case))
		for c in inst["link"]:
			check(s["grid"].get_tile(c) == "wall", "%s: the link cell %s is wall" % [str(case), str(c)])


func test_the_ghost_snaps_along_the_face_with_the_pointer() -> void:
	var s := _slope_ship("slope45", 0, false, 8)
	var a := _plan(s, "laser_mk1", 1.5, -3.0)
	var b := _plan(s, "laser_mk1", 1.5, 3.0)
	eq(a["why"], "", "the left end fits")
	eq(b["why"], "", "the right end fits")
	var moved: float = (Vector2(b["at"]) - Vector2(a["at"])).dot(s["t"])
	check(absf(moved - 6.0) < 1.5, "the barrel follows the pointer along the face (%.2f)" % moved)
	var near := Vector2(a["at"]) - (s["mid"] as Vector2)
	check(absf(near.dot(s["nrm"])) < 0.02, "the barrel's base lies on the face")


func test_it_refuses_a_short_or_broken_face_and_missing_floor() -> void:
	var short := _slope_ship("slope45", 0, false, 2)  # two cells: 2.83 along the face, the barrel is 4 wide
	eq(_plan(short)["why"], "the slope must be a straight face as wide as the barrel", "a 2-cell face is too short for a 4-wide barrel")
	var broken := _slope_ship("slope45", 0, false, 5)
	var cells: Array = broken["cells"]
	broken["grid"].breach(cells[2])  # a hole in the middle splits the face into two short runs
	eq(_plan(broken)["why"], "the slope must be a straight face as wide as the barrel", "a broken face is not one straight run")
	var bare := _slope_ship("slope45", 0, false, 5)
	for c in bare["grid"].tiles.keys():
		if bare["grid"].get_tile(c) == "floor":
			bare["grid"].force_tile(c, "")
	eq(_plan(bare)["why"], "needs free floor behind the slope", "no floor behind the slope")


func test_a_second_mount_cannot_overlap_the_first_but_can_sit_beside_it() -> void:
	var s := _slope_ship("slope45", 0, false, 9)
	var comps: Components = s["ship"].components
	var first := _plan(s, "laser_mk1", 1.5, -3.0)
	check(comps.place_planned("laser_mk1", first) >= 0, "the first one is placed")
	eq(_plan(s, "laser_mk1", 1.5, -2.0)["why"] != "", true, "right on top of it is refused")
	eq(_plan(s, "laser_mk1", 1.5, 3.0)["why"], "", "a few cells along there is room")


func test_a_straight_placement_is_unchanged_where_there_is_no_slope() -> void:
	var s := _slope_ship("slope45", 0, false, 4)
	var comps: Components = s["ship"].components
	var far := Vector2i(2, 2)  # nowhere near the slope
	var plan := comps.plan_mount_at(s["grid"], "laser_mk1", far, 0, Vector2(far) + Vector2(0.5, 0.5))
	eq(plan["why"], comps.plan_mount(s["grid"], "laser_mk1", far, 0)["why"], "the same refusal as the straight rule")
	check(not plan.has("angle"), "no angle without a slope")


# --- thrust ---------------------------------------------------------------------------------------------------------

func test_a_45_degree_engine_pushes_seventy_one_percent_forward_and_sideways() -> void:
	var f := Flight.new()
	for case in [[1, "left"], [2, "right"]]:  # on the rear corners: facing down-right pushes up and left, down-left pushes up and right
		var s := _slope_ship("slope45", case[0], false, 5)
		var comps: Components = s["ship"].components
		var uid := comps.place_planned("engine_mk1", _plan(s, "engine_mk1"))
		check(uid >= 0, "the engine is placed on the slope")
		var thrust := float(comps.def("engine_mk1")["stats"]["thrust"])
		var t := f.thrusts_of(comps, {uid: true})
		var other := "right" if case[1] == "left" else "left"
		near_val(float(t["fwd"]), thrust * 0.70711, "%s: forward 71%% of its thrust" % case[1], thrust * 0.005)
		near_val(float(t[case[1]]), thrust * (0.70711 + f.side_share), "%s: 71%% to that side plus the side share every engine gives" % case[1], thrust * 0.005)
		near_val(float(t[other]), thrust * f.side_share, "%s: only the side share the other way" % case[1], thrust * 0.005)


func test_a_1_to_2_slope_engine_splits_its_thrust_by_the_slope() -> void:
	var s := _slope_ship("slope2", 2, false, 5)  # angle 153.43: out down and to the right, 2 of 3 down
	var comps: Components = s["ship"].components
	var uid := comps.place_planned("engine_mk1", _plan(s, "engine_mk1"))
	var f := Flight.new()
	var thrust := float(comps.def("engine_mk1")["stats"]["thrust"])
	var t := f.thrusts_of(comps, {uid: true})
	near_val(float(t["fwd"]), thrust * 0.89443, "forward 89%", thrust * 0.005)
	near_val(float(t["left"]), thrust * (0.44721 + f.side_share), "left 45% plus the side share", thrust * 0.005)


func test_a_straight_mounts_direction_is_exact() -> void:
	eq(Mounts.dir_of({"rot": 2}), Vector2(0, 1), "a rear mount faces down, exactly")
	eq(Mounts.dir_of({"rot": 1, "angle": 90.0}), Vector2(1, 0), "an angle on a quarter turn is the straight rule")
	check(Mounts.dir_of({"rot": 0, "angle": 45.0}).is_equal_approx(Vector2(1, -1).normalized()), "45 degrees is up and right")


# --- guns -----------------------------------------------------------------------------------------------------------

func _armed(id: String, rot: int, mirror := false) -> Dictionary:
	var s := _slope_ship("slope45", rot, mirror, 5)
	var uid: int = s["ship"].components.place_planned(id, _plan(s, id))
	check(uid >= 0, id + " is placed on the slope")
	var a := Arena.new(7)
	a.add_ship(s["ship"], Vector2.ZERO)
	return {"arena": a, "uid": uid, "slope": s}


func test_a_gun_on_a_slope_aims_along_the_true_outward_direction() -> void:
	for rot in 4:
		var g := _armed("laser_mk1", rot)
		var a: Arena = g["arena"]
		var m: Dictionary = a.ships[0].mounts[g["uid"]]
		var want := Vector2.UP.rotated(deg_to_rad(45.0 + 90.0 * rot))
		check(Vector2(m["dir"]).is_equal_approx(want), "slope turned %d: dir is %s, got %s" % [rot, str(want), str(m["dir"])])
		eq(m["aim"], m["dir"], "and the barrel rests along it")
		var s: Dictionary = g["slope"]
		var inst: Dictionary = s["ship"].components.instances[g["uid"]]
		check((Vector2(m["pos"]) - Vector2(inst["out_at"])).dot(want) > 0.0, "slope turned %d: the barrel pivots in space, in front of the face" % rot)


func test_a_fixed_guns_gimbal_is_centred_on_the_slope() -> void:
	var g := _armed("laser_mk1", 0)  # faces 45 degrees: up and to the right; gimbal 5 degrees
	var a: Arena = g["arena"]
	var m: Dictionary = a.ships[0].mounts[g["uid"]]
	var from: Vector2 = a.local_to_world(0, m["pos"])
	check(a.weapons.in_arc(a, 0, m, from + Vector2.UP.rotated(deg_to_rad(45.0 + 4.0)) * 500.0), "4 degrees off the slope's way is inside the gimbal")
	check(not a.weapons.in_arc(a, 0, m, from + Vector2.UP.rotated(deg_to_rad(45.0 + 7.0)) * 500.0), "7 degrees off is outside")
	check(not a.weapons.in_arc(a, 0, m, from + Vector2.UP * 500.0), "straight up (45 degrees off) is far outside")


func test_a_45_degree_turrets_arc_is_centred_on_45_degrees() -> void:
	var g := _armed("laser_turret_mk1", 0)  # arc 270
	var a: Arena = g["arena"]
	var m: Dictionary = a.ships[0].mounts[g["uid"]]
	var from: Vector2 = a.local_to_world(0, m["pos"])
	eq(snappedf(rad_to_deg(Vector2.UP.angle_to(m["dir"])), 0.01), 45.0, "the arc's centre is 45 degrees")
	check(a.weapons.in_arc(a, 0, m, from + Vector2.UP.rotated(deg_to_rad(45.0 + 130.0)) * 500.0), "130 degrees round from the centre is inside")
	check(not a.weapons.in_arc(a, 0, m, from + Vector2.UP.rotated(deg_to_rad(45.0 + 140.0)) * 500.0), "140 degrees round is outside the 270 degree arc")
	check(a.weapons.in_arc(a, 0, m, from + Vector2.UP.rotated(deg_to_rad(45.0 - 130.0)) * 500.0), "and 130 degrees the other way is inside")


# --- damage ---------------------------------------------------------------------------------------------------------

func test_the_outside_half_on_a_slope_is_hit_by_the_cells_under_it_and_only_those() -> void:
	var g := _armed("laser_mk1", 0)
	var a: Arena = g["arena"]
	var co = a.ships[0]
	var inst: Dictionary = co.ship.components.instances[g["uid"]]
	check(inst["out_cells"].size() >= 5, "the turned barrel holds several cells (%d)" % inst["out_cells"].size())
	for c in inst["out_cells"]:
		var obj := Damage.solid_at(co, c)
		check(obj.get("uid", -1) == g["uid"] and obj.get("half", "") == "out", "the cell %s under the barrel is the barrel" % str(c))
	for c in [Vector2i(0, 0), inst["cells"][0], inst["link"][0] + Vector2i(1, 1) * 3]:
		check(Damage.solid_at(co, c).get("half", "") != "out", "the cell %s is not the barrel" % str(c))
	var cell: Vector2i = inst["out_cells"][0]
	Damage.apply(a, 0, cell, Damage.solid_at(co, cell), 999.0, "kinetic", {})
	check(not co.ship.components.outside_alive(g["uid"]), "enough damage disables the outside half")
	eq(co.ship.components.offline_reason(co.ship.grid, g["uid"]), "outside half disabled", "and the mount is offline")
	var behind := Collisions._behind_disabled(co, cell)
	check(co.ship.components.at_out(behind) != g["uid"], "a blow on the disabled barrel goes on to what is behind it")


func test_cutting_a_sloped_link_cell_cuts_the_mount_off() -> void:
	var g := _armed("laser_mk1", 0)
	var co = g["arena"].ships[0]
	var inst: Dictionary = co.ship.components.instances[g["uid"]]
	eq(co.ship.components.offline_reason(co.ship.grid, g["uid"]), "", "a whole link works")
	co.ship.grid.breach(inst["link"][0])
	eq(co.ship.components.offline_reason(co.ship.grid, g["uid"]), "link cut", "a breached sloped wall cell cuts it off")


# --- saves ----------------------------------------------------------------------------------------------------------

func test_the_angle_survives_a_save_and_an_old_save_loads_unchanged() -> void:
	var s := _slope_ship("slope2", 1, true, 4)
	var comps: Components = s["ship"].components
	var uid := comps.place_planned("laser_mk1", _plan(s))
	var before: Dictionary = comps.instances[uid].duplicate(true)
	var d: Dictionary = JSON.parse_string(JSON.stringify(comps.to_dict()))
	eq(int(d["version"]), Components.VERSION, "saved as the current version")
	check(d["instances"][0].has("angle"), "an angled mount saves its angle")
	var other := Components.new()
	other.load_defs(Ship.COMPONENTS_PATH)
	eq(other.load_dict(d), "", "loads")
	var inst: Dictionary = other.instances[uid]
	near_deg(float(inst["angle"]), float(before["angle"]), "same angle")
	eq(inst["rot"], before["rot"], "same quarter turn")
	eq(inst["anchor"], before["anchor"], "same breech")
	eq(inst["out_cells"], before["out_cells"], "same cells in space")
	eq(inst["link"], before["link"], "same link")
	check((Vector2(inst["out_at"]) - Vector2(before["out_at"])).length() < 1e-6, "same base middle")
	# a straight mount saves no angle, and a version 4 save (before angles) loads
	var wall := Components.new()
	wall.load_defs(Ship.COMPONENTS_PATH)
	var plain := {"version": 4, "next_uid": 2, "instances": [{"uid": 1, "id": "reactor_mk1", "anchor": [5, 5], "rot": 0, "hp": 10, "heat": 0.0, "status": "ok"}]}
	eq(wall.load_dict(plain), "", "an old save loads")
	check(not wall.to_dict()["instances"][0].has("angle"), "a straight part saves no angle")
	eq(int(wall.to_dict()["version"]), Components.VERSION, "and saves as the new version")


func test_undo_and_redo_keep_the_angled_mount() -> void:
	var s := _slope_ship("slope45", 0, false, 6)
	var ship: Ship = s["ship"]
	ship.inventory.add("laser_mk1", 1)
	var session := BuildSession.new(ship)
	var p: Vector2 = s["mid"] + s["nrm"] * 1.5
	var r := session.apply(session.plan_component("laser_mk1", Vector2i(int(floor(p.x)), int(floor(p.y))), 0, p)["changes"])
	eq(r["applied"], 1, "placed through the build session: " + str(r["reason"]))
	check(ship.components.instances.size() == 1 and Mounts.is_angled(ship.components.instances.values()[0]), "it sits on the slope")
	session.undo()
	eq(ship.components.instances.size(), 0, "undone")
	session.redo()
	eq(ship.components.instances.size(), 1, "redone")
	var inst: Dictionary = ship.components.instances.values()[0]
	check(Mounts.is_angled(inst) and not inst["link"].is_empty() and not inst["out_cells"].is_empty(), "with its angle, link and cells")
	var again := ship.components.link_at(inst["link"][0])
	check(again >= 0, "the link cell belongs to it")
	# a link cell of the slope cannot be walled over, and the barrel's cells cannot be built on
	var why := session.apply([{"layer": "tile", "cell": inst["link"][0], "to": "wall"}])
	eq(why["applied"], 0, "a sloped cell the mount stands on stays a slope")
	var air := session.apply([{"layer": "tile", "cell": inst["out_cells"][0], "to": "wall"}])
	eq(air["applied"], 0, "the barrel's space cannot be built on")


func near_deg(got: float, want: float, msg: String) -> void:
	near_val(wrapf(got - want, -180.0, 180.0), 0.0, msg, 0.01)


func near_val(got: float, want: float, msg: String, tol := 0.01) -> void:
	if absf(got - want) > tol:
		failures.append("%s: expected %s, got %s" % [msg, str(want), str(got)])
