extends "res://tests/base_test.gd"

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Components = preload("res://scripts/ship/components.gd")
const Cables = preload("res://scripts/ship/cables.gd")


## An 11x11 circular hull with floor on every hull cell.
func _grid(floored := true) -> ShipGrid:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(11, 11), defs)
	g.fill_circle_hull(5.0)
	if floored:
		for c in g.hull:
			g.place("floor", c)
	return g


func _comps() -> Components:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	return c


func test_data_is_complete() -> void:
	var c := _comps()
	var want := {
		"reactor_mk1": [8, 0, 1], "reactor_mk2": [14, 0, 2], "engine_mk1": [-2, 4, 1], "engine_mk2": [-3, 4, 2],
		"oxygen_gen": [-2, 1, 1], "shield_mk1": [-3, 3, 1], "laser_mk1": [-2, 5, 1], "laser_mk2": [-3, 5, 2],
		"helm": [-1, 2, 1], "medbay": [-2, 3, 1], "bed": [0, 0, 1], "fabricator": [-2, 6, 1],
		"robot_arm": [-1, 6, 1], "laser_cutter": [-2, 6, 1], "assembly_rig": [-2, 6, 1], "nanoforge": [-4, 6, 1],
	}
	eq(c.ids().size(), want.size(), "component count")
	for id in want:
		check(c.has(id), id + " exists")
		var d := c.def(id)
		eq([d["power"], d["priority"], d["tier"]], want[id], id + " power, priority, tier")
		for k in ["name", "size", "color", "family", "manned", "stats"]:
			check(d.has(k), "%s has %s" % [id, k])
	eq(c.def("reactor_mk1")["size"], [2, 2], "reactor is 2x2")
	eq(c.def("oxygen_gen")["size"], [1, 2], "oxygen generator is 1x2")
	eq(c.def("engine_mk2")["stats"]["thrust"], 18, "engine thrust")
	check(c.def("helm")["manned"], "the helm is manned")
	eq(c.def("nothing"), {}, "unknown id gives an empty def")


func test_footprint_rotation_swaps_size() -> void:
	var c := _comps()
	var a := Vector2i(3, 4)
	eq(c.footprint("engine_mk1", a, 0), [Vector2i(3, 4), Vector2i(4, 4)] as Array[Vector2i], "2x1 at rot 0")
	eq(c.footprint("engine_mk1", a, 1), [Vector2i(3, 4), Vector2i(3, 5)] as Array[Vector2i], "rot 1 makes it 1x2")
	eq(c.footprint("engine_mk1", a, 2), c.footprint("engine_mk1", a, 0), "rot 2 keeps the size")
	eq(c.footprint("engine_mk1", a, 3), c.footprint("engine_mk1", a, 1), "rot 3 swaps again")
	eq(c.footprint("engine_mk1", a, 4), c.footprint("engine_mk1", a, 0), "rot wraps at 4")
	eq(c.footprint("engine_mk1", a, -1), c.footprint("engine_mk1", a, 3), "negative rot wraps")
	eq(c.footprint("reactor_mk1", a, 1).size(), 4, "a 2x2 stays 4 cells")
	eq(c.footprint("oxygen_gen", a, 0), [Vector2i(3, 4), Vector2i(3, 5)] as Array[Vector2i], "1x2 at rot 0")
	eq(c.footprint("oxygen_gen", a, 1), [Vector2i(3, 4), Vector2i(4, 4)] as Array[Vector2i], "1x2 at rot 1 lies down")
	eq(c.footprint("nothing", a, 0).size(), 0, "unknown id has no cells")


func test_placement_needs_floor() -> void:
	var g := _grid(false)
	var c := _comps()
	eq(c.can_place(g, "reactor_mk1", Vector2i(4, 4), 0), "needs floor underneath", "bare hull")
	for p in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5)]:
		g.place("floor", p)
	eq(c.can_place(g, "reactor_mk1", Vector2i(4, 4), 0), "needs floor underneath", "one cell still bare")
	g.place("floor", Vector2i(5, 5))
	eq(c.can_place(g, "reactor_mk1", Vector2i(4, 4), 0), "", "all four cells floored")
	check(c.place(g, "reactor_mk1", Vector2i(4, 4), 0) > 0, "placed")
	eq(c.can_place(g, "nothing", Vector2i(4, 4), 0), "unknown component", "unknown id refused")
	eq(c.place(g, "nothing", Vector2i(4, 4), 0), -1, "unknown id not placed")


func test_placement_outside_the_hull() -> void:
	var g := _grid()
	var c := _comps()
	eq(c.can_place(g, "helm", Vector2i(0, 0), 0), "outside the hull", "corner is outside")
	eq(c.can_place(g, "engine_mk1", Vector2i(10, 5), 0), "outside the hull", "half off the grid")
	eq(c.can_place(g, "engine_mk1", Vector2i(-1, 5), 0), "outside the hull", "negative cells")
	eq(c.place(g, "helm", Vector2i(0, 0), 0), -1, "not placed")
	eq(c.instances.size(), 0, "nothing was added")


func test_walls_and_doors_are_not_floor() -> void:
	var g := _grid()
	var c := _comps()
	g.place("wall", Vector2i(4, 5))
	g.place("wall", Vector2i(6, 5))
	g.place("door", Vector2i(5, 5))
	eq(c.can_place(g, "helm", Vector2i(4, 5), 0), "needs floor underneath", "wall")
	eq(c.can_place(g, "helm", Vector2i(5, 5), 0), "needs floor underneath", "door")
	eq(c.can_place(g, "bed", Vector2i(4, 4), 0), "needs floor underneath", "wall under half the footprint")
	eq(c.can_place(g, "helm", Vector2i(5, 4), 0), "", "plain floor next to it")


func test_overlap_names_the_other_component() -> void:
	var g := _grid()
	var c := _comps()
	var r := c.place(g, "reactor_mk1", Vector2i(3, 3), 0)
	check(r > 0, "reactor placed")
	var want := "overlaps " + str(c.def("reactor_mk1")["name"])
	eq(c.can_place(g, "engine_mk1", Vector2i(4, 4), 0), want, "engine clips the reactor corner")
	eq(c.can_place(g, "reactor_mk2", Vector2i(3, 3), 0), want, "same cells")
	eq(c.place(g, "engine_mk1", Vector2i(4, 4), 0), -1, "overlap not placed")
	eq(c.can_place(g, "engine_mk1", Vector2i(5, 4), 0), "", "next to it is fine")
	eq(c.can_place(g, "engine_mk1", Vector2i(3, 5), 0), "", "below it is fine")
	var e := c.place(g, "engine_mk1", Vector2i(3, 5), 1)
	check(e > 0, "rotated engine placed")
	eq(c.can_place(g, "helm", Vector2i(3, 6), 0), "overlaps " + str(c.def("engine_mk1")["name"]), "rotated cells count")


func test_remove_frees_cells_and_uids_are_not_reused() -> void:
	var g := _grid()
	var c := _comps()
	var a := c.place(g, "engine_mk1", Vector2i(3, 3), 0)
	var b := c.place(g, "helm", Vector2i(3, 5), 0)
	eq(a, 1, "uids start at 1")
	eq(b, 2, "and count up")
	eq(c.at(Vector2i(4, 3)), a, "at() finds the second cell")
	eq(c.at(Vector2i(5, 3)), -1, "at() is -1 on a free cell")
	eq(c.remove_at(Vector2i(4, 3)), "engine_mk1", "remove by any covered cell")
	eq(c.remove_at(Vector2i(4, 3)), "", "nothing left to remove")
	eq(c.at(Vector2i(3, 3)), -1, "first cell freed")
	eq(c.at(Vector2i(4, 3)), -1, "second cell freed")
	check(not c.instances.has(a), "instance gone")
	eq(c.can_place(g, "engine_mk1", Vector2i(3, 3), 0), "", "the cells can be used again")
	var again := c.place(g, "engine_mk1", Vector2i(3, 3), 0)
	eq(again, 3, "a new uid, not the freed one")
	c.remove_at(Vector2i(3, 5))
	eq(c.place(g, "helm", Vector2i(3, 5), 0), 4, "uids are never reused")


func test_components_round_trip() -> void:
	var g := _grid()
	var c := _comps()
	c.place(g, "reactor_mk2", Vector2i(2, 3), 0)
	c.place(g, "engine_mk1", Vector2i(6, 3), 1)
	c.place(g, "oxygen_gen", Vector2i(6, 6), 3)
	var gone := c.place(g, "helm", Vector2i(4, 6), 0)
	c.remove_at(Vector2i(4, 6))
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	var h := _comps()
	eq(h.load_dict(d), "", "loads")
	eq(h.instances.size(), 3, "same count")
	for uid in c.instances:
		eq(h.instances[uid], c.instances[uid], "instance %d" % uid)
	eq(h.at(Vector2i(7, 4)), c.at(Vector2i(7, 4)), "cell index rebuilt")
	eq(h.to_dict(), c.to_dict(), "dicts match")
	var next := h.place(g, "helm", Vector2i(4, 6), 0)
	check(next > gone, "uid counter survives a round trip")
	eq(h.load_dict({"version": 99, "instances": []}), "unsupported components version", "future saves refused")
	eq(h.load_dict({"version": 1, "next_uid": 5, "instances": [{"uid": 1, "id": "warp_core", "anchor": [1, 1], "rot": 0}]}), "unknown component warp_core", "unknown ids refused")


func test_cables_place_remove_and_round_trip() -> void:
	var g := _grid()
	var comps := _comps()
	var cables := Cables.new()
	eq(cables.can_place(g, Vector2i(0, 0)), "outside the hull", "outside the hull")
	eq(cables.can_place(g, Vector2i(5, 5)), "", "free hull cell")
	check(cables.place(g, Vector2i(5, 5)), "placed")
	eq(cables.can_place(g, Vector2i(5, 5)), "already a cable", "no duplicates")
	check(not cables.place(g, Vector2i(5, 5)), "second place refused")
	g.place("wall", Vector2i(4, 5))
	g.place("wall", Vector2i(6, 5))
	g.place("door", Vector2i(5, 5))
	check(cables.has(Vector2i(5, 5)), "a cable under a door stays")
	check(cables.place(g, Vector2i(4, 5)), "cable under a wall")
	comps.place(g, "reactor_mk1", Vector2i(3, 2), 0)
	check(cables.place(g, Vector2i(4, 3)), "cable under a component")
	check(cables.place(g, Vector2i(9, 9)) == false, "outside the hull refused")
	var d: Dictionary = JSON.parse_string(JSON.stringify(cables.to_dict()))
	var back := Cables.new()
	eq(back.load_dict(d), "", "loads")
	eq(back.cells, cables.cells, "same cells")
	eq(back.to_dict(), cables.to_dict(), "dicts match")
	eq(back.load_dict({"version": 99}), "unsupported cables version", "future saves refused")
	check(back.remove(Vector2i(5, 5)), "removed")
	check(not back.remove(Vector2i(5, 5)), "nothing left to remove")
	eq(back.cells.size(), 2, "two cables left")
