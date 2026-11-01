extends "res://tests/base_test.gd"
## Hull mounts (docs/CONTENT.md 4f): a weapon or engine is two halves linked through a wall of any
## thickness. Placement and its refusals, saves (new and old), the outside half's own hp, the link,
## wrecked parts and the job that clears them. The aim, the thrust and the pilot are in test_aiming.gd.

const Wall = preload("res://tests/fixture_wall.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const Palette = preload("res://scripts/build/palette.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Components = preload("res://scripts/ship/components.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Damage = preload("res://scripts/combat/damage.gd")
const Projectiles = preload("res://scripts/combat/projectiles.gd")
const Collisions = preload("res://scripts/combat/collisions.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const Heat = preload("res://scripts/sim/heat.gd")
const Reliability = preload("res://scripts/sim/reliability.gd")

const WALLS: Array[int] = [1, 3, 5]


## A wall `thick` deep facing `rot` with a laser through it (outside half on u -2..1, the breech centred on u -1..0), a reactor behind it on
## u 2..3, and a cable between them. Returns {ship, uid, reactor, rot, thick, id}.
func _rig(thick := 1, rot := 0, id := "laser_mk1") -> Dictionary:
	var ship := Wall.wall_ship(thick, rot)
	var depth: int = ship.components.by_id[id]["mount"]["outside"][1]
	var uid := ship.components.place_mount(ship.grid, id, Wall.out_anchor(rot, depth), rot)
	var reactor := ship.components.place(ship.grid, "reactor_mk1", Wall.corner(rot, 2, 3, thick, thick + 3), rot % 2)
	for c in [Wall.at(rot, 0, thick), Wall.at(rot, 1, thick), Wall.at(rot, 2, thick)]:  # from the breech (u -1..0) to the reactor (u 2..3)
		ship.cables.place(ship.grid, c)
	ship.refresh()
	return {"ship": ship, "uid": uid, "reactor": reactor, "rot": rot, "thick": thick, "id": id}


func _arena(d: Dictionary) -> Arena:
	var a := Arena.new(1)
	a.add_ship(d["ship"])
	return a


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


# --- placement ----------------------------------------------------------------------------------------

func test_a_mount_goes_through_a_wall_of_any_thickness_in_all_four_directions() -> void:
	for rot in 4:
		for thick in WALLS:
			var ship := Wall.wall_ship(thick, rot)
			var out := Wall.out_anchor(rot)
			var plan: Dictionary = ship.components.plan_mount(ship.grid, "laser_mk1", out, rot)
			var tag := "rot %d, %d thick" % [rot, thick]
			eq(plan["why"], "", tag + ": it fits")
			eq(plan["depth"], thick, tag + ": the link is the whole wall")
			eq(plan["link"].size(), 4 * thick, tag + ": across the full width")
			eq(plan["anchor"], Wall.corner(rot, -1, 0, thick, thick + 1), tag + ": the 2x2 breech sits centred behind the barrel, on the first floor rows behind the wall")
			var uid: int = ship.components.place_mount(ship.grid, "laser_mk1", out, rot)
			check(uid >= 0, tag + ": placed")
			var inst: Dictionary = ship.components.instances[uid]
			eq(inst["cells"].size(), 4, tag + ": the inside half is 2x2 (a tier 1 laser)")
			eq(inst["out_cells"].size(), 8, tag + ": and so is the outside half")
			eq(inst["out_hp"], 10, tag + ": the outside half has its own hp (twice the part's 5)")
			eq(ship.components.at(inst["cells"][0]), uid, tag + ": the inside half answers at()")
			eq(ship.components.at_out(inst["out_cells"][0]), uid, tag + ": the outside half answers at_out()")
			eq(ship.components.at(inst["out_cells"][0]), -1, tag + ": and not at()")
			eq(ship.components.any_at(inst["out_cells"][0]), uid, tag + ": either half answers any_at()")
			eq(ship.components.link_at(inst["link"][0]), uid, tag + ": the wall knows it is mounted through")
			for c in inst["out_cells"]:
				check(ship.grid.get_tile(c) == "", tag + ": the barrel is in space")
			eq(Mounts.outward(rot), [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][rot], tag + ": outward turns with the part")


func test_the_heavy_shrapnel_cannon_has_a_three_row_outside_half() -> void:
	var ship := Wall.wall_ship(2)
	var out := Wall.out_anchor(0, 3)
	var uid: int = ship.components.place_mount(ship.grid, "shrapnel_cannon_scrap", out, 0)
	check(uid >= 0, "placed")
	var inst: Dictionary = ship.components.instances[uid]
	eq([inst["cells"].size(), inst["out_cells"].size()], [4, 12], "a 2x2 inside half and a 4x3 outside half")
	eq(inst["out_hp"], 12, "twice the part's 6")
	eq(inst["anchor"], Wall.corner(0, -1, 0, 2, 3), "the breech is centred, two rows behind a two-thick wall")


func test_every_mount_has_halves_that_share_their_width_and_a_known_outside_hp() -> void:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	var n := 0
	for id in c.ids():
		var d := c.def(id)
		if d["family"] in ["weapon", "engine", "intake", "radar", "tractor"]:
			n += 1
			check(Mounts.is_mount(d), id + " is a hull mount")
			var narrow: bool = d["size"][0] == 2  # a tier 1-2 gun or engine (2x2 behind a 4 wide barrel, playtest 2 P2), Strafe Jets (2x2 and 2x2, docs/waves/engines_1.md)
			eq(d["size"], [2, 2] if narrow else [4, 2], id + ": the inside half is 4x2 (a Strafe Jets one 2x2)")
			var console: bool = d["family"] == "radar" and not narrow  # a Radar Mk2 or Mk3 console is 4x2 behind a 2x2 dish (art/README.md)
			var small_barrel: bool = id.begins_with("strafe") or id == "net_mouth_scrap" or id == "radar_mk1" or console  # these have a 2 wide outside half
			eq(d["mount"]["outside"][0], 2 if small_barrel else 4, id + ": the barrel is 4 wide (a Strafe Jets, a net mouth or a radar's dish is 2 wide)")
			if not console:
				check(d["mount"]["outside"][0] >= d["size"][0], id + ": the barrel is at least as wide as the breech")
			if d["family"] == "weapon":  # an armoured barrel housing (the balance pass: at 75% a bow gun went at the first volley)
				eq(d["mount"]["outside_hp"], 2 * int(d["hp"]), id + ": a weapon's outside_hp is twice its hp")
			else:
				eq(d["mount"]["outside_hp"], int(floor(d["hp"] * 0.75 + 0.5)), id + ": outside_hp is 75 percent of hp, rounded")
		else:
			check(not Mounts.is_mount(d), id + " is a plain part")
	check(n >= 19, "every weapon, engine, intake, radar and tractor was checked (%d)" % n)
	eq(c.def("shrapnel_cannon_scrap")["mount"]["outside"], [4, 3], "the Shrapnel Cannon's outside half is 4x3")


func test_the_refusals_say_why_on_every_thickness_and_in_every_direction() -> void:
	for rot in 4:
		for thick in WALLS:
			_refusals(thick, rot)


func _refusals(thick: int, rot: int) -> void:
	var ship := Wall.wall_ship(thick, rot)
	var parts: Components = ship.components
	var ok := Wall.out_anchor(rot)
	var tag := "rot %d, %d thick" % [rot, thick]
	var toward := Vector2i(Mounts.outward(rot))  # one step out into space
	var breech := "the breech needs 2x2 free floor behind the wall"  # a tier 1 laser's breech: square, so it reads the same turned
	eq(parts.can_place_mount(ship.grid, "laser_mk1", ok, rot), "", tag + ": the plain case works")
	# the barrel must stick out into space
	eq(parts.can_place_mount(ship.grid, "laser_mk1", ok - toward, rot), "the barrel must stick out into space", tag + ": an outside half that overlaps the wall")
	eq(parts.can_place_mount(ship.grid, "laser_mk1", Vector2i(-1, 5), rot), "the barrel must stick out into space", tag + ": an outside half off the grid")
	var first: int = parts.place_mount(ship.grid, "laser_mk1", ok, rot)
	var along := Wall.at(rot, 2, 0) - Wall.at(rot, 0, 0)
	eq(parts.can_place_mount(ship.grid, "laser_mk1", ok + along, rot), "the barrel must stick out into space", tag + ": an outside half on another gun's")
	parts.remove_uid(first)
	# needs a flat wall to mount through
	eq(parts.can_place_mount(ship.grid, "laser_mk1", ok + toward, rot), "needs a flat wall to mount through", tag + ": a gap between the barrel and the wall")
	var layer0 := Wall.at(rot, 0, 0)
	ship.grid.force_tile(layer0, "floor")
	eq(parts.can_place_mount(ship.grid, "laser_mk1", ok, rot), "needs a flat wall to mount through", tag + ": a floor cell in the first wall layer")
	ship.grid.force_tile(layer0, "door")
	eq(parts.can_place_mount(ship.grid, "laser_mk1", ok, rot), "needs a flat wall to mount through", tag + ": a door in it")
	ship.grid.force_tile(layer0, "wall")
	ship.grid.set_shape(layer0, "tri", 0, false)
	eq(parts.can_place_mount(ship.grid, "laser_mk1", ok, rot), "needs a flat wall to mount through", tag + ": a sloped cell in it")
	ship.grid.set_shape(layer0, "full")
	ship.grid.force_tile(layer0, "wall")
	eq(parts.can_place_mount(ship.grid, "laser_mk1", ok, rot), "", tag + ": mended")
	# the breech needs 4x2 free floor behind the wall
	ship.grid.force_tile(Wall.at(rot, 0, thick), "")
	eq(parts.can_place_mount(ship.grid, "laser_mk1", ok, rot), breech, tag + ": a hole in the floor behind")
	ship.grid.force_tile(Wall.at(rot, 0, thick), "floor")
	var gen: int = parts.place(ship.grid, "oxygen_gen", Wall.corner(rot, 0, 1, thick, thick + 3), rot % 2)
	check(gen >= 0, tag + ": (setup: a generator behind the wall)")
	eq(parts.can_place_mount(ship.grid, "laser_mk1", ok, rot), breech, tag + ": another part in the way")
	var solid := Wall.wall_ship(thick, rot)  # metal all the way back: no room for the breech
	for d in range(thick, thick + 6):
		for u in range(-7, 8):
			solid.grid.force_tile(Wall.at(rot, u, d), "wall")
	eq(solid.components.can_place_mount(solid.grid, "laser_mk1", ok, rot), breech, tag + ": a wall with solid metal behind it, no room")
	eq(parts.can_place_mount(ship.grid, "reactor_mk1", ok, rot), "not a hull mount", tag + ": a reactor is not a mount")
	eq(parts.can_place_mount(ship.grid, "warp_core", ok, rot), "unknown component", tag + ": unknown ids")


# --- a breech narrower than the barrel (tier 1-2 guns and engines: 2 wide behind a 4 wide outside half) ----

## laser_mk1 with a 2x2 breech: the data-independent shape of the rule.
func _narrow(id := "laser_mk1") -> Dictionary:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	var d: Dictionary = c.def(id).duplicate(true)
	d["size"] = [2, 2]
	return d


## The breech's cells' extent along the wall, as (first, last) grid coordinates of the wall's axis.
func _span(cells: Array, rot: int) -> Vector2i:
	var lo := 1 << 20
	var hi := -(1 << 20)
	for c in cells:
		var v: int = c.x if rot % 2 == 0 else c.y
		lo = mini(lo, v)
		hi = maxi(hi, v)
	return Vector2i(lo, hi)


func test_a_narrow_breech_sits_centred_behind_the_barrel_at_every_rotation_and_wall() -> void:
	var def := _narrow()
	for rot in 4:
		for thick in WALLS:
			var ship := Wall.wall_ship(thick, rot)
			var out := Wall.out_anchor(rot)
			var plan: Dictionary = Mounts.plan(ship.grid, ship.components, def, out, rot)
			var tag := "rot %d, %d thick" % [rot, thick]
			eq(plan["why"], "", tag + ": it fits")
			eq(plan["depth"], thick, tag + ": the link is the whole wall")
			eq(plan["link"].size(), 4 * thick, tag + ": and as wide as the barrel (4), not the breech")
			eq(plan["out_cells"].size(), 8, tag + ": the barrel is 4x2")
			eq(plan["cells"].size(), 4, tag + ": the breech is 2x2")
			eq(plan["anchor"], Wall.corner(rot, -1, 0, thick, thick + 1), tag + ": centred behind the barrel (u -1..0 of -2..1), on the first floor rows")
			var b := _span(plan["out_cells"], rot)
			var i := _span(plan["cells"], rot)
			eq([i.x - b.x, b.y - i.y], [1, 1], tag + ": one cell of barrel to either side of the breech")


func test_a_narrow_breech_refuses_when_its_two_columns_are_not_free_floor() -> void:
	var def := _narrow()
	for rot in 4:
		var ship := Wall.wall_ship(1, rot)
		var out := Wall.out_anchor(rot)
		var tag := "rot %d" % rot
		eq(Mounts.plan(ship.grid, ship.components, def, out, rot)["why"], "", tag + ": plain")
		ship.grid.force_tile(Wall.at(rot, -1, 1), "")  # a hole in the breech's floor
		eq(Mounts.plan(ship.grid, ship.components, def, out, rot)["why"], "the breech needs 2x2 free floor behind the wall", tag + ": a hole under the breech")
		ship.grid.force_tile(Wall.at(rot, -1, 1), "floor")
		ship.grid.force_tile(Wall.at(rot, -2, 1), "")  # floor missing beside the breech, behind the barrel's end: fine
		eq(Mounts.plan(ship.grid, ship.components, def, out, rot)["why"], "", tag + ": the barrel's end need not have floor behind it")
		ship.grid.force_tile(Wall.at(rot, 1, 0), "floor")  # a wall that is not flat across the barrel's width, beside the breech
		eq(Mounts.plan(ship.grid, ship.components, def, out, rot)["why"], "needs a flat wall to mount through", tag + ": the wall run is as wide as the barrel")


func test_a_narrow_breech_only_needs_its_own_cells_clear() -> void:
	var def := _narrow()
	var ship := Wall.wall_ship(2)
	var out := Wall.out_anchor(0)
	var gen: int = ship.components.place(ship.grid, "oxygen_gen", Wall.corner(0, 0, 1, 2, 5), 0)
	check(gen >= 0, "(setup: a generator on u 0..1 behind the wall, half of it on the breech)")
	eq(Mounts.plan(ship.grid, ship.components, def, out, 0)["why"], "the breech needs 2x2 free floor behind the wall", "a part on the breech's cells")
	ship.components.remove_uid(gen)
	var beside: int = ship.components.place(ship.grid, "helm", Wall.corner(0, -3, -2, 2, 3), 0)
	check(beside >= 0, "(setup: a 2x2 helm on u -3..-2, under the barrel's left end but beside the breech)")
	eq(Mounts.plan(ship.grid, ship.components, def, out, 0)["why"], "", "a part under the barrel's width but not the breech's does not matter")


func test_plan_from_inside_and_cells_of_agree_for_a_narrow_breech_at_every_rotation() -> void:
	var def := _narrow()
	for rot in 4:
		for thick in WALLS:
			var ship := Wall.wall_ship(thick, rot)
			var out := Wall.out_anchor(rot)
			var plan: Dictionary = Mounts.plan(ship.grid, ship.components, def, out, rot)
			var tag := "rot %d, %d thick" % [rot, thick]
			var back: Dictionary = Mounts.from_inside(ship.grid, ship.components, def, plan["anchor"], rot)
			eq(back["why"], "", tag + ": from_inside finds it")
			eq(back["out"], out, tag + ": the outside half's top-left comes back")
			eq(back["anchor"], plan["anchor"], tag + ": the same breech")
			eq(back["depth"], thick, tag + ": the same wall depth")
			eq(back["link"], plan["link"], tag + ": the same link")
			var saved: Dictionary = Mounts.cells_of(def, plan["anchor"], rot, out)
			eq(saved["depth"], thick, tag + ": cells_of reads the depth back")
			eq(saved["out_cells"], plan["out_cells"], tag + ": the same barrel cells")
			eq(saved["cells"], plan["cells"], tag + ": the same breech cells")
			eq(saved["link"], plan["link"], tag + ": the same link cells")
			eq(Mounts.cells_of(def, plan["anchor"] + Vector2i(1, 1), rot, out), {}, tag + ": a breech that is not behind the barrel is no mount")


func test_from_inside_looks_through_the_whole_barrel_width_like_plan_does() -> void:
	var def := _narrow()
	for rot in 4:
		var ship := Wall.wall_ship(3, rot)
		var inside := Wall.corner(rot, -1, 0, 3, 4)  # an old save's breech, on the first floor rows behind the wall
		var tag := "rot %d" % rot
		var back: Dictionary = Mounts.from_inside(ship.grid, ship.components, def, inside, rot)
		eq([back["why"], back["depth"], back["out"]], ["", 3, Wall.out_anchor(rot)], tag + ": the three layers and the barrel in space")
		ship.grid.force_tile(Wall.at(rot, -2, 2), "floor")  # the barrel's end column is not wall in the last layer; the breech's own columns are
		eq(Mounts.from_inside(ship.grid, ship.components, def, inside, rot)["why"], "needs a flat wall to mount through", tag + ": the walk covers the barrel's width, so this is no wall to mount through")


func test_the_barrel_pivot_is_read_from_the_outside_half_only() -> void:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	var wide: Dictionary = c.def("laser_mk1")
	var narrow := _narrow()
	for rot in 4:
		var a: Dictionary = Mounts.barrel(narrow, Vector2i(5, 5), rot)
		var b: Dictionary = Mounts.barrel(wide, Vector2i(5, 5), rot)
		eq(a["pivot"], b["pivot"], "rot %d: the same pivot with a narrow breech" % rot)
		eq(a["reach"], b["reach"], "rot %d: and the same reach" % rot)


func test_wreckage_blocks_the_floor_behind_the_wall() -> void:
	var ship := Wall.wall_ship(1)
	var inside := Wall.corner(0, -1, 0, 1, 2)
	ship.components.wrecks.append({"id": "reactor_mk1", "cells": [inside + Vector2i(1, 0)]})
	eq(ship.components.can_place_mount(ship.grid, "laser_mk1", Wall.out_anchor(0), 0), "the breech needs 2x2 free floor behind the wall", "debris on the floor")
	eq(ship.components.can_place(ship.grid, "bed", inside, 0), "wreckage in the way", "and for any other part")
	eq(ship.components.place(ship.grid, "bed", inside, 0), -1, "place() agrees")


func test_the_build_session_places_mounts_by_their_outside_half_and_undoes_them() -> void:
	var ship := Wall.wall_ship(2)
	var s := BuildSession.new(ship)
	var out := Wall.out_anchor(0)
	var r := s.apply([{"layer": "component", "id": "laser_mk1", "anchor": out, "rot": 0}])
	eq(r, {"applied": 1, "skipped": 0, "reason": ""}, "placed in one step")
	eq(ship.inventory.count("laser_mk1"), 1, "one laser used")
	var uid: int = ship.components.any_at(out)
	check(uid >= 0, "the outside half is where it was pointed")
	eq(ship.components.instances[uid]["anchor"], Wall.corner(0, -1, 0, 2, 3), "the inside half was found")
	var before := JSON.stringify(ship.to_dict())
	eq(s.apply([{"layer": "component", "id": "laser_mk1", "anchor": out + Vector2i(0, -5), "rot": 0}])["reason"], "needs a flat wall to mount through", "a second one in mid air is refused")
	eq(s.preview([{"layer": "component", "id": "laser_mk1", "anchor": out + Vector2i(4, 0), "rot": 0}])[0]["reason"], "", "the ghost of a free spot would apply")
	eq(JSON.stringify(ship.to_dict()), before, "a preview changes nothing")
	check(s.undo(), "undo")
	eq([ship.inventory.count("laser_mk1"), ship.components.instances.size()], [2, 0], "the laser is back and the mount is gone")
	check(s.redo(), "redo")
	eq(ship.components.any_at(out), uid, "the same uid, the same place")
	# removing by a cell of either half takes both
	var inside_cell: Vector2i = ship.components.instances[uid]["cells"][0]
	eq(s.apply([{"layer": "component", "cell": inside_cell}])["applied"], 1, "removed by its inside half")
	eq(ship.components.at_out(out), -1, "and the barrel went with it")
	s.undo()
	eq(s.apply([{"layer": "component", "cell": out}])["applied"], 1, "removed by its outside half")
	check(ship.components.instances.is_empty(), "nothing left")
	s.undo()
	check(ship.components.any_at(out) >= 0, "undo brings both back")


func test_build_mode_points_at_the_outside_half_and_shows_both_halves_and_the_reason() -> void:
	var ship := Wall.wall_ship(3)
	var sim := ShipSim.new()
	sim.ships = [ship]
	var b := BuildMode.new()
	b.sim = sim
	b.group = BuildMode.Group.SYSTEMS
	b._fix_component()
	b.sel_component = "laser_mk1"
	b.rot = 0
	b.hover = Wall.out_anchor(0)
	b._refresh_ghost()
	eq(b.ghost.size(), 1, "one ghost for the one item")
	eq(b.ghost[0]["reason"], "", "the barrel in space against a 3-thick wall would apply")
	var place: String = Palette.info(b.selected_entry(), ship, b.rot)["place"]
	check(place.contains("outside half 4x2, pointing up"), "the selection card names the outside half and the direction: " + place)
	b.hover = Wall.out_anchor(0) + Vector2i(0, 2)  # the barrel on the wall itself
	b._refresh_ghost()
	eq(b.ghost[0]["reason"], "the barrel must stick out into space", "refused with its reason")
	check(b.cursor_note()["text"].contains("can't: the barrel must stick out into space"), "and the note at the cursor says it")
	b.hover = Wall.out_anchor(0)
	b._refresh_ghost()
	b._build_key(KEY_R)
	eq(b.rot, 1, "R turns it a quarter")
	b._refresh_ghost()
	eq(b.ghost[0]["reason"], "the barrel must stick out into space", "turned sideways its taller barrel sinks into the wall")
	b._build_key(KEY_R)
	b._build_key(KEY_R)
	b._build_key(KEY_R)
	eq(b.rot, 0, "four quarter turns")
	b._refresh_ghost()
	b.dragging = true
	b.drag_button = MOUSE_BUTTON_LEFT
	b.drag_mode = BuildSession.Mode.PAINT
	b.drag_start = b.hover
	b.drag_path = [b.hover]
	b._end_drag()
	check(ship.components.any_at(b.hover) >= 0, "a click places it by its outside half")
	b.drag_button = MOUSE_BUTTON_RIGHT
	b.dragging = true
	b._end_drag()
	check(ship.components.instances.is_empty(), "and a right click on either half takes it away")
	sim.free()
	b.free()


func test_the_wall_a_mount_stands_through_cannot_be_taken_away() -> void:
	var d := _rig(2)
	var s := BuildSession.new(d["ship"])
	var link: Vector2i = d["ship"].components.instances[d["uid"]]["link"][0]
	var name: String = d["ship"].components.def("laser_mk1")["name"]
	eq(s.apply([{"layer": "tile", "cell": link, "to": ""}])["reason"], "a %s is mounted through this wall" % name, "no removing it")
	eq(s.apply([{"layer": "tile", "cell": link, "to": "floor"}])["reason"], "a %s is mounted through this wall" % name, "no floor in it")
	eq(s.apply([{"layer": "tile", "cell": link, "to": "scrap_plate"}])["applied"], 1, "but any other wall material will do")
	eq(d["ship"].components.link_intact(d["ship"].grid, d["uid"]), true, "still linked")
	var barrel: Vector2i = d["ship"].components.instances[d["uid"]]["out_cells"][0]
	eq(s.apply([{"layer": "tile", "cell": barrel, "to": "wall"}])["reason"], "a %s sticks out here" % name, "nothing is built on the barrel")


# --- saves ----------------------------------------------------------------------------------------------

func test_a_mount_survives_a_save_and_load_with_its_halves_and_its_damage() -> void:
	for rot in 4:
		var d := _rig(2, rot)
		var ship: Ship = d["ship"]
		var inst: Dictionary = ship.components.instances[d["uid"]]
		inst["out_hp"] = 1
		inst["hp"] = 3
		var saved: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))
		var rec: Dictionary = saved["components"]["instances"][0]
		eq(saved["components"]["version"], Components.VERSION, "the current components version (5: angles)")
		eq(Vector2i(int(rec["out"][0]), int(rec["out"][1])), inst["out_anchor"], "a record keeps the outside half's top-left")
		eq(Vector2i(int(rec["anchor"][0]), int(rec["anchor"][1])), inst["anchor"], "and the inside half's")
		eq(rec["rot"], rot, "and the rotation")
		eq(rec["out_hp"], 1, "and the outside half's hp")
		var back := Ship.new("Back", Wall.wall_ship(2, rot).grid)
		eq(back.load_dict(saved), "", "loads")
		var got: Dictionary = back.components.instances[d["uid"]]
		eq([got["out_anchor"], got["anchor"], got["rot"], got["out_hp"], got["hp"]], [inst["out_anchor"], inst["anchor"], rot, 1, 3], "everything came back")
		eq(got["out_cells"], inst["out_cells"], "the outside cells")
		eq(got["link"], inst["link"], "and the link")
		eq(JSON.stringify(back.to_dict()), JSON.stringify(ship.to_dict()), "and it saves back the same")


func test_wrecks_are_saved() -> void:
	var d := _rig()
	d["ship"].components.wrecks.append({"id": "bed", "cells": [Vector2i(5, 5), Vector2i(5, 6)]})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(d["ship"].to_dict()))
	var back := Ship.new("Back", Wall.wall_ship(1).grid)
	eq(back.load_dict(saved), "", "loads")
	eq(back.components.wrecks, [{"id": "bed", "cells": [Vector2i(5, 5), Vector2i(5, 6)]}], "the debris is still there")


## The ship `d` as a version 2 save would have it: no outside halves.
func _old_save(d: Dictionary) -> Dictionary:
	var saved: Dictionary = JSON.parse_string(JSON.stringify(d["ship"].to_dict()))
	saved["components"]["version"] = 2
	for i in saved["components"]["instances"]:
		i.erase("out")
		i.erase("out_hp")
	return saved


func test_an_old_save_gets_its_weapons_and_engines_mounted_through_the_wall() -> void:
	for rot in 4:
		var d := _rig(2, rot)
		d["ship"].components.instances[d["uid"]]["hp"] = 2
		var old := _old_save(d)
		var back := Ship.new("Back", Wall.wall_ship(2, rot).grid)
		eq(back.load_dict(old), "", "loads (rot %d)" % rot)
		check(back.components.instances.has(d["uid"]), "the laser is still aboard")
		var got: Dictionary = back.components.instances[d["uid"]]
		eq([got["out_anchor"], got["out_cells"], got["rot"]], [d["ship"].components.instances[d["uid"]]["out_anchor"], d["ship"].components.instances[d["uid"]]["out_cells"], rot], "mounted by the same rule: where it would have been placed")
		eq([got["hp"], got["out_hp"]], [2, 10], "its hp kept, the new outside half whole")
		eq(back.inventory.count("laser_mk1"), 2, "nothing went to the cargo")


func test_an_old_save_with_no_wall_puts_the_part_back_in_the_cargo_and_says_so() -> void:
	var d := _rig(2)
	var old := _old_save(d)
	for t in old["tiles"]:
		if t[2] == "wall" and Rect2i(Wall.corner(0, -7, 7, 0, 1), Vector2i(15, 2)).has_point(Vector2i(int(t[0]), int(t[1]))):
			t[2] = "floor"  # the wall is gone
	var back := Ship.new("Back", Wall.wall_ship(2).grid)
	var held: int = d["ship"].inventory.count("laser_mk1")  # the save's cargo
	eq(back.load_dict(old), "", "loads")
	check(not back.components.instances.has(d["uid"]), "the laser is no longer placed")
	check(back.components.instances.has(d["reactor"]), "the rest is")
	eq(back.inventory.count("laser_mk1"), held + 1, "it is in the cargo")
	check(back.events.any(func(e): return e["text"].contains("went back to the cargo")), "and the chronicle says so: %s" % str(back.events))


func test_an_old_save_turned_the_other_way_round_is_mounted_on_the_far_wall() -> void:
	# an engine saved at rotation 0 whose wall is on its other side (nozzles down): the rule tries the opposite turn
	var ship := Wall.wall_ship(1, 2)
	var uid := ship.components.place_mount(ship.grid, "engine_mk1", Wall.out_anchor(2), 2)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))
	saved["components"]["version"] = 1
	for i in saved["components"]["instances"]:
		i.erase("out")
		i.erase("out_hp")
		i["rot"] = 0
	var back := Ship.new("Back", Wall.wall_ship(1, 2).grid)
	eq(back.load_dict(saved), "", "loads")
	eq(back.components.instances[uid]["rot"], 2, "turned to face the wall's outer side")
	eq(back.components.instances[uid]["out_cells"], ship.components.instances[uid]["out_cells"], "and mounted there")


# --- the outside half ---------------------------------------------------------------------------------

func test_the_outside_half_takes_the_hits_and_is_only_ever_disabled() -> void:
	var d := _rig(2)
	var a := _arena(d)
	var ship: Ship = d["ship"]
	var inst: Dictionary = ship.components.instances[d["uid"]]
	var barrel: Vector2i = inst["out_cells"][0]
	var co = a.ships[0]
	var obj := Damage.solid_at(co, barrel)
	eq([obj["kind"], obj["half"], obj["uid"]], ["component", "out", d["uid"]], "a shot meets the outside half first")
	Damage.apply(a, 0, barrel, obj, 9.0, "energy")
	eq([float(inst["out_hp"]), inst["hp"], inst["status"]], [1.0, 5, "ok"], "it took the damage, the inside half did not")
	check(co.powered.get(d["uid"], false), "still powered and working")
	Damage.apply(a, 0, barrel, obj, 9.0, "energy")
	eq(inst["out_hp"], 0, "at 0 it is disabled")
	check(a.events.any(func(e): return e["type"] == "disable" and e.get("half", "") == "out" and e["uid"] == d["uid"]), "and the event says so")
	a.sync(0)
	eq(a.weapons.status_of(a, 0, d["uid"]), "disabled", "the gun is out of action")
	check(not co.powered.get(d["uid"], false), "and draws no power")
	eq(a.weapons.can_fire(a, 0, d["uid"], Vector2(0, -1000)), "disabled", "it cannot fire")
	eq(ship.components.offline_reason(ship.grid, d["uid"]), "outside half disabled", "the reason")
	eq(Damage.solid_at(co, barrel), {}, "a shot now passes through the disabled barrel")
	check(not Damage.solid_at(co, barrel, true).is_empty(), "though it still counts for the hull's shape")
	Damage.apply(a, 0, barrel, {"kind": "component", "uid": d["uid"], "half": "out"}, 99.0, "kinetic")
	check(ship.components.instances.has(d["uid"]) and ship.components.wrecks.is_empty(), "no hit ever wrecks an outside half")
	eq(inst["out_hp"], 0, "it stays at 0")


func test_a_shot_at_a_disabled_barrel_hits_the_wall_behind_it() -> void:
	var d := _rig(2)
	var inst: Dictionary = d["ship"].components.instances[d["uid"]]
	var a := Arena.new(1)
	a.add_ship(d["ship"], Vector2.ZERO)
	a.add_ship(Wall.wall_ship(1), Vector2(0.0, -3000.0))  # the shooter
	var w := {"kind": "laser", "damage_type": "kinetic", "damage": 1.0, "pierce": 0, "range": 2000.0, "shots": 1, "turret": false, "gimbal": 180.0}
	var from: Vector2 = a.cell_to_world(0, Wall.at(0, 0, -6))
	var to: Vector2 = a.cell_to_world(0, Wall.at(0, 0, 4))
	Projectiles.trace(a, 1, w, from, to)
	eq(a.events.filter(func(e): return e["type"] == "hit")[0]["kind"], "component", "a working barrel is hit first")
	inst["out_hp"] = 0
	a.events.clear()
	Projectiles.trace(a, 1, w, from, to)
	var hits: Array = a.events.filter(func(e): return e["type"] == "hit")
	check(not hits.is_empty(), "the shot hit something")
	eq(hits[0]["kind"], "wall", "the wall behind the barrel, not the barrel")
	eq(inst["out_hp"], 0, "the disabled barrel took nothing more")


func test_a_repair_from_inside_heals_the_outside_half_first_when_the_link_is_whole() -> void:
	var d := _rig(2)
	var ship: Ship = d["ship"]
	var inst: Dictionary = ship.components.instances[d["uid"]]
	inst["out_hp"] = 0
	inst["hp"] = 0
	inst["status"] = "disabled"
	check(ship.outside_hurt(d["uid"]), "the barrel needs repair")
	check(ship.repair(d["uid"]), "one repair")
	eq([inst["out_hp"], inst["hp"], inst["status"]], [10, 0, "disabled"], "mends the outside half first")
	check(not ship.outside_hurt(d["uid"]), "now only the inside half does")
	ship.repair(d["uid"])
	eq([inst["out_hp"], inst["hp"], inst["status"]], [10, 5, "ok"], "the second mends the inside half")
	# with the link cut the outside half cannot be reached
	inst["out_hp"] = 1
	ship.grid.breach(inst["link"][0])
	check(not ship.outside_hurt(d["uid"]), "no repair of the barrel through a hole")
	ship.repair(d["uid"])
	eq(inst["out_hp"], 1, "and a repair then does not heal it")


func test_the_crew_repair_a_hurt_barrel_from_the_inside_and_patch_a_cut_link_first() -> void:
	var d := _rig(2)
	var ship: Ship = d["ship"]
	var inst: Dictionary = ship.components.instances[d["uid"]]
	inst["out_hp"] = 1
	var jobs := Jobs.new()
	jobs.build_board(ship)
	check(jobs.board.has("fix:%d" % d["uid"]), "a repair job for a part that works but whose barrel is hurt")
	eq(jobs.board["fix:%d" % d["uid"]]["cells"], inst["cells"], "worked on from the inside half")
	var cut: Vector2i = inst["link"][3]
	ship.grid.breach(cut)
	jobs.build_board(ship)
	check(not jobs.board.has("fix:%d" % d["uid"]), "none while the link is cut")
	check(jobs.board.has("breach:%d,%d" % [cut.x, cut.y]), "the breach comes first")
	ship.grid.repair(cut)
	jobs.build_board(ship)
	check(jobs.board.has("fix:%d" % d["uid"]), "and then the barrel")
	# a crew member does it
	var m := CrewMember.new("Ada", Pathfinder.centre_of(Wall.corner(0, 4, 5, 5, 6)))
	ship.crew.append(m)
	for i in 160:
		jobs.tick(ship, 0.1)
	eq(inst["out_hp"], 10, "the barrel is whole after a while")
	check(ship.events.any(func(e): return e["text"].ends_with("repaired")), "and the chronicle says so")


func test_a_breached_link_cell_takes_the_mount_offline_until_it_is_patched() -> void:
	var d := _rig(3)
	var a := _arena(d)
	var ship: Ship = d["ship"]
	var co = a.ships[0]
	check(co.powered.get(d["uid"], false), "it works")
	var cell: Vector2i = ship.components.instances[d["uid"]]["link"][5]
	var tile: String = ship.grid.tiles[cell]
	Damage.apply(a, 0, cell, Damage.solid_at(co, cell), 99.0, "kinetic")
	check(ship.grid.breached.has(cell), "a shot opened the wall")
	a.sync(0)
	eq(ship.components.offline_reason(ship.grid, d["uid"]), "link cut", "the link is cut")
	check(not co.powered.get(d["uid"], false), "no power reaches it")
	eq(a.weapons.can_fire(a, 0, d["uid"], Vector2(0, -1000)), "offline", "it cannot fire")
	eq(ship.components.instances[d["uid"]]["out_hp"], 10, "though its barrel is fine")
	check(ship.grid.repair(cell), "the crew patch the breach")
	ship.mark_dirty()
	a.sync(0)
	eq(ship.grid.get_tile(cell), tile, "the wall is back")
	check(co.powered.get(d["uid"], false), "and the mount with it")
	eq(a.weapons.can_fire(a, 0, d["uid"], Vector2(0, -1000)), "", "ready to fire")


func test_the_outside_half_is_part_of_the_hitbox_and_the_mass() -> void:
	var d := _rig(1, 0, "leech_laser")  # a 4x2 + 4x2 mount that weighs by its cells (the tier 1-2 guns are listed in flight.json at their old mass)
	var with: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(with)
	var cells: Array = Collisions.hit_cells(a, 0)["cells"]
	var barrel: Array = with.components.instances[d["uid"]]["out_cells"]
	var outer := barrel.filter(func(c): return cells.has(c))
	eq(outer.size(), 6, "the barrel's outer cells (all but the two between the others and the wall) are collision cells")
	with.components.instances[d["uid"]]["out_hp"] = 0
	a.ships[0].hit_cache = {}
	eq(barrel.filter(func(c): return Collisions.hit_cells(a, 0)["cells"].has(c)).size(), 6, "and a disabled barrel still is")
	var f = a.ships[0].flight
	var m_with: float = f.mass_of(with.grid, with.components, with.cables)
	var bare := Wall.wall_ship(1)  # the same ship with the laser's inside half only
	bare.components.place(bare.grid, "leech_laser", with.components.instances[d["uid"]]["anchor"], 0)
	bare.components.place(bare.grid, "reactor_mk1", with.components.instances[d["reactor"]]["anchor"], 0)
	for u in 3:
		bare.cables.place(bare.grid, Wall.at(0, u, 1))
	near(m_with - f.mass_of(bare.grid, bare.components, bare.cables), 8.0 * f.component_mass_per_cell, "the outside half weighs 8 cells more", 1e-6)


func test_a_ram_on_a_disabled_barrel_goes_on_into_the_wall_behind_it() -> void:
	for rot in 4:
		var d := _rig(2, rot)
		var a := _arena(d)
		var inst: Dictionary = d["ship"].components.instances[d["uid"]]
		var barrel: Vector2i = Wall.at(rot, -1, -1)  # the cell of the barrel against the wall
		eq(Collisions._behind_disabled(a.ships[0], barrel), barrel, "rot %d: a working barrel takes the blow itself" % rot)
		inst["out_hp"] = 0
		var first: Vector2i = Wall.at(rot, -1, 0)
		eq(Collisions._behind_disabled(a.ships[0], barrel), first, "rot %d: a disabled one passes it to the wall cell behind it" % rot)
		eq(Collisions._behind_disabled(a.ships[0], Wall.at(rot, -1, -2)), first, "rot %d: from the outer row of the barrel too" % rot)
		eq(Collisions._behind_disabled(a.ships[0], first), first, "rot %d: a wall cell is just itself" % rot)


# --- wrecked parts ------------------------------------------------------------------------------------

func test_a_disabled_part_hit_again_is_wrecked_and_leaves_debris() -> void:
	var d := _rig(2)
	var a := _arena(d)
	var ship: Ship = d["ship"]
	var co = a.ships[0]
	var inst: Dictionary = ship.components.instances[d["reactor"]]
	var cell: Vector2i = inst["cells"][5]
	var cells: Array = inst["cells"].duplicate()
	Damage.apply(a, 0, cell, Damage.solid_at(co, cell), 8.0, "kinetic")
	eq([float(inst["hp"]), inst["status"]], [0.0, "disabled"], "8 damage disables a reactor of 8 hp")
	Damage.apply(a, 0, cell, Damage.solid_at(co, cell), 1.0, "kinetic")
	check(ship.components.instances.has(d["reactor"]), "a second hit in the same instant does not wreck it")
	a.step(0.1)
	Damage.apply(a, 0, cell, Damage.solid_at(co, cell), 1.0, "kinetic")
	check(not ship.components.instances.has(d["reactor"]), "the next hit does")
	eq(ship.components.wrecks, [{"id": "reactor_mk1", "cells": cells}], "debris on its cells")
	check(ship.components.wreck_at(cells[0]) >= 0 and ship.components.wreck_at(Vector2i(0, 0)) < 0, "wreck_at finds it")
	check(Damage.solid_at(co, cell).is_empty(), "the cells are open floor again")
	check(a.events.any(func(e): return e["type"] == "wreck_part" and e["id"] == "reactor_mk1"), "the arena says so")
	check(ship.events.any(func(e): return e["text"].contains("wrecked")), "and so does the chronicle")


func test_splash_wrecks_too_but_ion_never_does() -> void:
	var d := _rig(2)
	var a := _arena(d)
	var ship: Ship = d["ship"]
	var co = a.ships[0]
	var inst: Dictionary = ship.components.instances[d["reactor"]]
	inst["hp"] = 0
	inst["status"] = "disabled"
	var cell: Vector2i = inst["cells"][5]
	Damage.apply(a, 0, cell, Damage.solid_at(co, cell), 50.0, "ion")
	check(ship.components.instances.has(d["reactor"]), "ion does no structural damage: no wreck")
	a.step(0.1)
	Damage.splash(a, 0, inst["cells"][0] + _beside(inst), 2.0, 1.5, "explosive")
	check(not ship.components.instances.has(d["reactor"]), "but a blast next to it wrecks it")


## A cell next to the part's first cell, off the part.
func _beside(inst: Dictionary) -> Vector2i:
	for dir in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
		if not inst["cells"].has(inst["cells"][0] + dir):
			return dir
	return Vector2i.ZERO


func test_fire_heat_and_malfunctions_only_ever_disable() -> void:
	var d := _rig(2)
	var ship: Ship = d["ship"]
	var inst: Dictionary = ship.components.instances[d["reactor"]]
	inst["hp"] = 0
	inst["status"] = "disabled"
	Fire.ignite(ship, inst["cells"][5])
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 300:
		Fire.tick(ship, 0.1, rng)
		Heat.tick(ship, 0.1)
		Reliability.tick(ship, 0.1, rng)
	check(ship.components.instances.has(d["reactor"]), "a fire on a disabled part does not wreck it")
	eq(inst["status"], "disabled", "it is still just disabled")
	check(ship.components.wrecks.is_empty(), "no debris")


func test_wrecking_the_inside_half_of_a_mount_removes_both_halves() -> void:
	var d := _rig(2)
	var a := _arena(d)
	var ship: Ship = d["ship"]
	var co = a.ships[0]
	var inst: Dictionary = ship.components.instances[d["uid"]]
	var inside: Array = inst["cells"].duplicate()
	var barrel: Array = inst["out_cells"].duplicate()
	inst["hp"] = 0
	inst["status"] = "disabled"
	var cell: Vector2i = inside[0]
	Damage.apply(a, 0, cell, Damage.solid_at(co, cell), 1.0, "energy")
	check(not ship.components.instances.has(d["uid"]), "the part is gone")
	for c in barrel:
		eq(ship.components.any_at(c), -1, "the barrel at %s broke off" % str(c))
	check(not co.mounts.has(d["uid"]), "it is no longer a weapon")
	eq(ship.components.wrecks.size(), 1, "one wreck")
	eq(ship.components.wrecks[0]["cells"], inside, "debris only where the crew can reach: the inside half")
	check(ship.components.link_at(Wall.at(0, 0, 0)) < 0, "and the wall is only a wall again")


func test_a_ram_on_a_disabled_part_counts_as_a_direct_hit() -> void:
	var d := _rig(2)
	var a := _arena(d)
	var ship: Ship = d["ship"]
	var inst: Dictionary = ship.components.instances[d["reactor"]]
	inst["hp"] = 0
	inst["status"] = "disabled"
	var cell: Vector2i = inst["cells"][0]
	a.step(0.1)
	Damage.apply(a, 0, cell, Damage.solid_at(a.ships[0], cell), 0.01, "kinetic", {"ram": true})
	check(not ship.components.instances.has(d["reactor"]), "any ram damage at all wrecks a part that is already out")


# --- clearing the debris ---------------------------------------------------------------------------------

## A rig whose reactor was swapped for part `id`, wrecked, with two crew beside the debris. Returns {ship, jobs, id}.
func _wrecked(id: String) -> Dictionary:
	var d := _rig(2)
	var ship: Ship = d["ship"]
	ship.components.remove_uid(d["reactor"])
	var size: Array = ship.components.def(id)["size"]
	var uid: int = ship.components.place(ship.grid, id, Wall.corner(0, 2, 1 + size[0], 2, 1 + size[1]), 0)
	ship.components.wreck(uid)
	for k in 2:  # one goes to man the laser (priority 50), the other is free for the debris (30)
		ship.crew.append(CrewMember.new(["Ada", "Bram"][k], Pathfinder.centre_of(Wall.corner(0, 6 - 11 * k, 7 - 11 * k, 5, 6))))
	return {"ship": ship, "jobs": Jobs.new(), "id": id}


func test_the_crew_clear_the_debris_and_get_half_the_recipe_back_rounded_down() -> void:
	var w := _wrecked("reactor_mk1")  # 30 scrap and 15 copper
	var ship: Ship = w["ship"]
	var jobs: Jobs = w["jobs"]
	var scrap: int = ship.inventory.count("scrap")
	var copper: int = ship.inventory.count("copper")
	jobs.build_board(ship)
	var key := "wreck:%d,%d" % [ship.components.wrecks[0]["cells"][0].x, ship.components.wrecks[0]["cells"][0].y]
	check(jobs.board.has(key), "the debris is a job")
	eq([jobs.board[key]["type"], jobs.board[key]["priority"], jobs.board[key]["work"]], ["clear_wreck", 30, 4.0], "clear_wreck: priority 30, 4 s")
	for i in 120:
		jobs.tick(ship, 0.1)
	check(ship.components.wrecks.is_empty(), "the debris is cleared")
	eq([ship.inventory.count("scrap") - scrap, ship.inventory.count("copper") - copper], [15, 7], "15 scrap and 7 copper: half of 30 and half of 15, rounded down")
	check(ship.events.any(func(e): return e["text"].begins_with("Cleared the wreck of Reactor Mk1")), "the chronicle: %s" % str(ship.events.map(func(e): return e["text"])))
	check(ship.components.can_place(ship.grid, "bed", Wall.corner(0, 2, 3, 2, 5), 0) != "wreckage in the way", "the floor is free again")


func test_a_unique_part_gives_nothing_back() -> void:
	var w := _wrecked("mirror_veil")
	var ship: Ship = w["ship"]
	var jobs: Jobs = w["jobs"]
	check(ship.components.def(w["id"]).get("unique", false), "the part is a unique")
	var before := ship.inventory.to_dict()
	for i in 120:
		jobs.tick(ship, 0.1)
	check(ship.components.wrecks.is_empty(), "the debris is cleared")
	eq(ship.inventory.to_dict(), before, "and nothing came out of it")
	eq(ship.wreck_refund("afterburner"), {}, "an Afterburner is a unique too")


func test_the_refund_of_each_recipe_is_half_rounded_down() -> void:
	var ship := Wall.wall_ship(1)
	for id in ["engine_mk1", "laser_mk1", "rattle_burst_scrap", "bed", "helm"]:
		var mats: Dictionary = ship.crafting.def(id).get("materials", {})
		var want := {}
		for m in mats:
			if floori(float(mats[m]) / 2.0) > 0:
				want[m] = floori(float(mats[m]) / 2.0)
		eq(ship.wreck_refund(id), want, id + ": half the recipe, rounded down")
