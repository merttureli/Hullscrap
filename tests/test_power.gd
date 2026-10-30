extends "res://tests/base_test.gd"

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Components = preload("res://scripts/ship/components.gd")
const Cables = preload("res://scripts/ship/cables.gd")
const Power = preload("res://scripts/sim/power.gd")

var grid: ShipGrid
var comps: Components
var cables: Cables


## A 31x31 circular hull with floor on every hull cell, no components and no cables.
func _setup() -> void:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	grid = ShipGrid.new(Vector2i(31, 31), defs)
	grid.fill_circle_hull(15.0)
	for c in grid.hull:
		grid.place("floor", c)
	comps = Components.new()
	comps.load_defs("res://data/components.json")
	cables = Cables.new()


func _put(id: String, x: int, y: int, rot := 0) -> int:
	var uid := comps.place(grid, id, Vector2i(x, y), rot)
	check(uid > 0, "%s placed at %d,%d" % [id, x, y])
	return uid


## Cables on every cell of the rectangle x0..x1, y0..y1.
func _wire(x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			check(cables.place(grid, Vector2i(x, y)), "cable at %d,%d" % [x, y])


func _net(r: Dictionary, uid: int) -> Dictionary:
	return r["networks"][r["network_of"][uid]]


func test_reactor_and_engine_on_a_cable() -> void:
	_setup()
	var r := _put("reactor_mk1", 6, 12)  # x 6..9
	var e := _put("engine_mk1", 11, 12)  # x 11..14
	_wire(9, 12, 12, 12)
	var res := Power.solve(comps, cables)
	check(res["powered"][r], "reactor powered")
	check(res["powered"][e], "engine powered")
	eq(res["networks"].size(), 1, "one network")
	eq(res["network_of"][r], res["network_of"][e], "same network")
	var n: Dictionary = res["networks"][0]
	eq(n["id"], 0, "ids start at 0")
	eq(n["members"], [r, e], "members by uid")
	eq(n["cells"].size(), 4, "four cable cells")
	eq([n["supply"], n["demand"], n["used"]], [8, 2, 2], "supply, demand, used")


func test_no_cable_means_no_power() -> void:
	_setup()
	var r := _put("reactor_mk1", 6, 12)
	var e := _put("engine_mk1", 11, 12)
	var res := Power.solve(comps, cables)
	check(not res["powered"][r], "reactor off a network is unpowered")
	check(not res["powered"][e], "engine without a cable is unpowered")
	eq(res["networks"].size(), 0, "no networks")
	eq(res["network_of"].size(), 0, "no memberships")
	_wire(9, 12, 10, 12)
	res = Power.solve(comps, cables)
	check(res["powered"][r], "reactor on the cable is powered")
	check(not res["powered"][e], "engine not touching the cable stays off")
	eq(res["networks"][0]["demand"], 0, "an unconnected engine adds no demand")


func test_zero_power_parts_need_a_network_too() -> void:
	_setup()
	var on := _put("bed", 6, 6)
	var off := _put("bed", 18, 18)
	_wire(6, 6, 6, 6)
	var res := Power.solve(comps, cables)
	check(res["powered"][on], "a bed on a network counts as powered")
	check(not res["powered"][off], "a bed off every network does not")


func test_cutting_a_cable_unpowers_the_far_side() -> void:
	_setup()
	var r := _put("reactor_mk1", 4, 12)  # x 4..7
	var near := _put("engine_mk1", 10, 13)
	var far := _put("engine_mk1", 20, 13)
	_wire(7, 13, 20, 13)
	var res := Power.solve(comps, cables)
	eq(res["networks"].size(), 1, "joined")
	check(res["powered"][far], "far engine powered")
	check(cables.remove(Vector2i(16, 13)), "cut")
	res = Power.solve(comps, cables)
	eq(res["networks"].size(), 2, "split in two")
	check(res["powered"][r] and res["powered"][near], "near side still powered")
	check(not res["powered"][far], "far engine lost power")
	eq(_net(res, far)["supply"], 0, "the far network has no supply")
	check(res["network_of"][far] != res["network_of"][r], "different networks")
	check(cables.place(grid, Vector2i(16, 13)), "mend")
	res = Power.solve(comps, cables)
	eq(res["networks"].size(), 1, "joined again")
	check(res["powered"][far], "far engine powered again")


func test_shortfall_powers_by_priority() -> void:
	_setup()
	var r := _put("reactor_mk1", 14, 2)
	var lasers := []
	for y in [6, 8, 10, 12]:
		lasers.append(_put("laser_mk1", 15, y))
	var o2 := _put("oxygen_gen", 15, 15)
	_wire(15, 2, 15, 19)
	var res := Power.solve(comps, cables)
	check(res["powered"][r], "reactor on")
	check(res["powered"][o2], "oxygen generator goes first despite the higher uid")
	for i in 3:
		check(res["powered"][lasers[i]], "laser %d powered" % i)
	check(not res["powered"][lasers[3]], "the last laser is the one left dark")
	eq([res["networks"][0]["supply"], res["networks"][0]["demand"], res["networks"][0]["used"]], [8, 10, 8], "supply, demand, used")


func test_equal_priority_goes_by_uid() -> void:
	_setup()
	_put("reactor_mk1", 14, 2)
	var a := _put("laser_mk2", 15, 6)
	var b := _put("laser_mk2", 15, 8)
	var c := _put("laser_mk2", 15, 10)
	_wire(15, 2, 15, 11)
	var res := Power.solve(comps, cables)
	check(res["powered"][a] and res["powered"][b], "the two oldest fit")
	check(not res["powered"][c], "the newest does not")


func test_a_later_small_consumer_still_fits() -> void:
	_setup()
	_put("reactor_mk1", 14, 2)
	var e1 := _put("engine_mk2", 15, 6)
	var e2 := _put("engine_mk2", 15, 8)
	var laser := _put("laser_mk2", 15, 10)
	var fab := _put("fabricator", 15, 12)
	_wire(15, 2, 15, 13)
	var res := Power.solve(comps, cables)
	check(res["powered"][e1] and res["powered"][e2], "engines first (priority 4)")
	check(not res["powered"][laser], "the laser (3) no longer fits in the 2 left")
	check(res["powered"][fab], "the fabricator (2) still fits after it")
	eq([res["networks"][0]["demand"], res["networks"][0]["used"]], [11, 8], "demand and used")


func test_two_reactors_add_up() -> void:
	_setup()
	_put("reactor_mk1", 14, 2)
	_put("reactor_mk2", 14, 6)
	var ids := []
	for pair in [["engine_mk2", 10], ["engine_mk2", 12], ["shield_mk1", 14], ["laser_mk2", 18], ["laser_mk2", 20]]:
		ids.append(_put(pair[0], 15, pair[1]))
	_wire(15, 2, 15, 21)
	var res := Power.solve(comps, cables)
	eq(res["networks"][0]["supply"], 22, "8 + 14")
	eq(res["networks"][0]["demand"], 15, "demand")
	for uid in ids:
		check(res["powered"][uid], "uid %d powered" % uid)
	var one := Components.new()
	one.load_defs("res://data/components.json")
	var d := comps.to_dict()
	d["instances"].remove_at(1)
	one.load_dict(d)
	var res1 := Power.solve(one, cables)
	eq(res1["networks"][0]["supply"], 8, "one reactor alone is 8")
	check(not res1["powered"][ids[4]], "and cannot run everything")


func test_a_disabled_reactor_makes_no_power() -> void:
	_setup()
	var r1 := _put("reactor_mk1", 14, 2)
	var r2 := _put("reactor_mk2", 14, 6)
	var e := _put("engine_mk1", 15, 10)
	_wire(15, 2, 15, 11)
	var res := Power.solve(comps, cables, {r2: true})
	eq(res["networks"][0]["supply"], 8, "only the mk1 supplies")
	check(not res["powered"][r2], "a disabled reactor is not powered")
	check(res["powered"][r1] and res["powered"][e], "the rest still run")
	res = Power.solve(comps, cables, {r1: true, r2: true})
	eq(res["networks"][0]["supply"], 0, "no reactor, no supply")
	check(not res["powered"][e], "engine dark")
	eq(res["network_of"][r1], 0, "a disabled part is still a network member")
	res = Power.solve(comps, cables, {e: true})
	check(not res["powered"][e], "a disabled consumer is unpowered")
	eq([res["networks"][0]["demand"], res["networks"][0]["used"]], [0, 0], "and uses nothing")
	res = Power.solve(comps, cables, {r1: false})
	check(res["powered"][r1], "false means not disabled")


## Reactor on cable A (row 13), engine on cable B (row 16); a 4x4 shield sits over the gap and
## touches both runs.
func _bridge_scene() -> Dictionary:
	_setup()
	var s := {}
	s["reactor"] = _put("reactor_mk1", 2, 12)
	s["engine"] = _put("engine_mk1", 16, 15)
	_wire(2, 13, 11, 13)
	_wire(12, 16, 19, 16)
	return s


func test_a_bridging_component_merges_networks() -> void:
	var s := _bridge_scene()
	var res := Power.solve(comps, cables)
	eq(res["networks"].size(), 2, "two separate networks")
	check(res["powered"][s["reactor"]], "reactor powered")
	check(not res["powered"][s["engine"]], "engine on the other network is not")
	var shield := _put("shield_mk1", 10, 13)
	res = Power.solve(comps, cables)
	eq(res["networks"].size(), 1, "the shield joins them")
	check(res["powered"][s["engine"]], "engine now powered")
	check(res["powered"][shield], "shield powered")
	eq(res["network_of"][s["reactor"]], res["network_of"][s["engine"]], "same network id")
	eq(_net(res, shield)["members"], [s["reactor"], s["engine"], shield], "all three are members")
	eq(_net(res, shield)["cells"].size(), 18, "both cable runs are one network")
	eq([_net(res, shield)["supply"], _net(res, shield)["demand"], _net(res, shield)["used"]], [8, 5, 5], "supply, demand, used")
	comps.remove_at(Vector2i(10, 13))
	res = Power.solve(comps, cables)
	eq(res["networks"].size(), 2, "removing it splits them again")


func test_a_disabled_part_still_bridges() -> void:
	var s := _bridge_scene()
	var shield := _put("shield_mk1", 10, 13)
	var res := Power.solve(comps, cables, {shield: true})
	eq(res["networks"].size(), 1, "still one network")
	check(res["powered"][s["engine"]], "engine powered through the disabled shield")
	check(not res["powered"][shield], "the shield itself is off")


func test_result_does_not_depend_on_insertion_order() -> void:
	var s := _bridge_scene()
	var shield := _put("shield_mk1", 10, 13)
	_wire(6, 24, 13, 24)
	_put("reactor_mk2", 6, 23)
	var laser := _put("laser_mk2", 12, 24)
	var d := comps.to_dict()
	d["instances"].reverse()
	var other := Components.new()
	other.load_defs("res://data/components.json")
	eq(other.load_dict(d), "", "loads shuffled")
	check(other.instances.keys() != comps.instances.keys(), "the instance order really differs")
	var cd := cables.to_dict()
	cd["cells"].reverse()
	var other_cables := Cables.new()
	other_cables.load_dict(cd)
	check(other_cables.cells.keys() != cables.cells.keys(), "the cable order really differs")
	for dis in [{}, {laser: true}, {shield: true}]:
		var a := Power.solve(comps, cables, dis)
		var b := Power.solve(other, other_cables, dis)
		eq(b, a, "same result")
		eq(str(b), str(a), "same result, same ordering")
	var res := Power.solve(comps, cables)
	eq(res["networks"].size(), 2, "the bridge scene and the extra run")
	eq(res["networks"][0]["id"], 0, "first network id")
	check(res["network_of"][laser] == 1, "the lower run comes second in reading order")
	check(res["network_of"][s["engine"]] == 0, "the upper network comes first")
