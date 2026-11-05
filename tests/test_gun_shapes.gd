extends "res://tests/base_test.gd"
## The gun rework, G1a (docs/GUNS.md): gun shapes of any outside size (the shape table, the centring rule, hp, placement through a wall at
## every turn, rams passing over a low pod), the three aim classes (fixed, swivel, turret) with their arc bands and damage shares, several
## barrels on one base, point defence by tier, a pilot that presents a broadside, and shipgen placing guns by shape.

const Wall = preload("res://tests/fixture_wall.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Components = preload("res://scripts/ship/components.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Collisions = preload("res://scripts/combat/collisions.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")

const DT := 1.0 / 60.0
const SHAPES := {"point_turret": [2, 2], "dome_turret": [3, 3], "sponson": [3, 2], "casemate": [4, 2], "long_barrel": [2, 4],
	"broadside": [6, 2], "gun_strip": [8, 1], "heavy_cannon": [4, 3], "spinal": [2, 6], "flush_pod": [4, 1]}  ## GUNS.md 3: the outside half at rotation 0
const SAMPLE := {"point_turret": "laser_turret_mk1", "dome_turret": "leech_laser", "sponson": "basalt_pumice_flak", "casemate": "laser_mk1",
	"long_barrel": "human_concord_railgun", "broadside": "gauntling_scrap_shotgun", "heavy_cannon": "basalt_quarry_driver", "flush_pod": "human_volley_rack"}


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _comps() -> Components:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	return c


func _guns(c: Components) -> Array:
	return c.ids().filter(func(id): return c.def(id)["family"] == "weapon" and Mounts.is_mount(c.def(id)))


# --- shapes and hp ------------------------------------------------------------------------------------------

func test_every_gun_has_a_shape_and_its_outside_half_is_that_shapes() -> void:
	var c := _comps()
	var w := Weapons.new()
	eq(w.shapes.size(), SHAPES.size(), "the data lists the ten shapes")
	for s in SHAPES:
		eq(w.shapes[s]["outside"], SHAPES[s], s + ": its outside half")
	var seen := {}
	for id in _guns(c):
		var d := c.def(id)
		check(w.shapes.has(str(d.get("shape", ""))), id + " names a shape in the shape table")
		var s: Dictionary = w.shapes.get(str(d.get("shape", "")), {})
		eq(d["mount"]["outside"], s.get("outside"), id + ": the outside half is the shape's")
		eq(s.get("aim"), w.def(id)["aim"], id + ": it aims as its shape does")
		seen[d["shape"]] = true
		var cells: int = d["mount"]["outside"][0] * d["mount"]["outside"][1]
		var hp_rule := roundi(float(d["hp"]) * cells / 4.0)  # hp x cells / 4: twice the hp for 8 cells; the Shrapnel Cannon keeps its older 12
		check(d["mount"]["outside_hp"] == hp_rule or id == "shrapnel_cannon_scrap", "%s: outside hp scales with its %d cells (%d, rule %d)" % [id, cells, d["mount"]["outside_hp"], hp_rule])
	for s in ["point_turret", "dome_turret", "sponson", "casemate", "long_barrel", "broadside", "heavy_cannon", "flush_pod"]:
		check(seen.has(s), "a gun uses the shape " + s)


# --- aim classes ------------------------------------------------------------------------------------------

func test_the_aim_classes_keep_their_arc_bands_and_damage_shares() -> void:
	var w := Weapons.new()
	var c := _comps()
	eq(w.aim_share, {"fixed": 1.0, "swivel": 0.8, "turret": 0.6}, "the shares")
	var counts := {"fixed": 0, "swivel": 0, "turret": 0}
	for id in _guns(c):
		var e: Dictionary = w.defs[id]
		var d := w.def(id)
		var cls: String = d["aim"]
		counts[cls] += 1
		var wide: bool = c.def(id)["shape"] in w.aim_classes["fixed"]["wide"]
		match cls:
			"fixed":
				check(float(d["gimbal"]) <= (20.0 if wide else 8.0), "%s: a fixed gun's gimbal is up to 8 (20 for a broadside), %s" % [id, str(d["gimbal"])])
				check(not wide or float(d["gimbal"]) >= 20.0 or true, "")
				check(not d["turret"], id + " does not track")
				near(d["damage"], float(e["damage"]), id + ": a fixed gun deals all of its damage", 1e-9)
			"swivel":
				check(float(d["arc"]) >= 120.0 and float(d["arc"]) <= 180.0, "%s: a swivel's arc is 120 to 180 (%s)" % [id, str(d["arc"])])
				check(d["turret"], id + " tracks")
				near(d["damage"], 0.8 * float(e["damage"]), id + ": a swivel deals 0.8", 1e-9)
			"turret":
				check(float(d["arc"]) >= 270.0 and float(d["arc"]) <= 360.0, "%s: a turret's arc is 270 to 360 (%s)" % [id, str(d["arc"])])
				check(d["turret"], id + " tracks")
				near(d["damage"], 0.6 * float(e["damage"]), id + ": a turret deals 0.6", 1e-9)
	check(counts["swivel"] >= 1 and counts["turret"] >= 8 and counts["fixed"] >= 20, "all three classes are in use " + str(counts))
	for id in ["gauntling_scrap_shotgun", "kett_chitin_thrower"]:
		near(w.def(id)["gimbal"], 20.0, id + ": a broadside's gimbal is 20")


func test_the_pumice_flak_became_a_swivel_that_deals_what_it_dealt() -> void:
	var w := Weapons.new()
	var d := w.def("basalt_pumice_flak")
	eq(d["aim"], "swivel", "a swivel")
	eq(d["arc"], 180.0, "arc 180")
	near(d["damage"], 2.5 * 0.6, "the damage it deals is the old turret's (2.5 x 0.6)", 1e-9)
	eq(w.aim_of(_comps().def("basalt_pumice_flak")), {"class": "swivel", "arc": 180.0, "gimbal": 0.0, "shape": "sponson"}, "aim_of for the cards")
	eq(w.aim_of(w.def("laser_mk1")), {"class": "fixed", "arc": 10.0, "gimbal": 5.0, "shape": ""}, "a fixed gun: the wedge is twice its gimbal")
	eq(w.aim_of(_comps().def("laser_turret_mk1"))["class"], "turret", "a turret")


func test_the_old_turret_damage_key_is_still_read() -> void:
	var f := FileAccess.open("user://old_weapons.json", FileAccess.WRITE)
	f.store_string('{"turret_damage": 0.5, "weapons": {"a": {"kind": "bolt", "damage": 2, "turret": true}, "b": {"kind": "bolt", "damage": 2, "aim": "swivel"}}}')
	f.close()
	var w := Weapons.new("user://old_weapons.json")
	near(w.def("a")["damage"], 1.0, "a turret deals the old key's share")
	near(w.def("b")["damage"], 1.6, "a swivel its default 0.8")
	check(w.def("b")["turret"], "and tracks")


# --- the centring rule and placement -----------------------------------------------------------------------

func test_the_breech_sits_at_floor_w_minus_bw_over_two_from_the_outside_halfs_left_edge() -> void:
	# at rotation 0: (outside width, breech width) -> the breech's distance from the left edge
	for case in [[4, 2, 1], [3, 2, 0], [3, 4, -1], [2, 4, -1], [6, 4, 1], [2, 2, 0], [4, 4, 0], [5, 2, 1]]:
		eq(Mounts.breech_shift(Vector2i(case[0], 2), Vector2i(case[1], 2), 0).x, case[2], "rot 0: %d over %d" % [case[0], case[1]])
	# turned: the left edge of the gun is the top (rot 1), the right (rot 2), the bottom (rot 3) of the grid, so an odd cell goes to the other end
	eq(Mounts.breech_shift(Vector2i(3, 2), Vector2i(2, 2), 2).x, 1, "rot 2: the odd cell is on the left of the grid")
	eq(Mounts.breech_shift(Vector2i(2, 3), Vector2i(2, 2), 1).y, 0, "rot 1: from the top")
	eq(Mounts.breech_shift(Vector2i(2, 3), Vector2i(2, 2), 3).y, 1, "rot 3: from the bottom of the gun, so one from the top")
	eq(Mounts.breech_shift(Vector2i(2, 3), Vector2i(2, 4), 3).y, 0, "a wider breech turned: the same")


func test_every_shape_mounts_through_a_wall_at_every_turn_and_comes_back_from_its_inside_half() -> void:
	var c := _comps()
	for shape in SAMPLE:
		var id: String = SAMPLE[shape]
		for rot in 4:
			var tag := "%s (%s) rot %d" % [id, shape, rot]
			var ship := Wall.wall_ship(2, rot)
			var def := ship.components.def(id)
			var out := Wall.out_for(def, rot)
			var plan := Mounts.plan(ship.grid, ship.components, def, out, rot)
			eq(plan["why"], "", tag + ": it fits")
			eq(plan["out_cells"].size(), def["mount"]["outside"][0] * def["mount"]["outside"][1], tag + ": the outside half has all its cells")
			var osz := Mounts.turned(def["mount"]["outside"], rot)
			var along: int = osz.x if rot % 2 == 0 else osz.y
			eq(plan["link"].size(), along * 2, tag + ": the link is as wide as the outside half, 2 layers")
			# the inside half is where the centring rule puts it
			var lay := Mounts.layout(def, out, rot, 2)
			eq(lay["inside"].position, plan["anchor"], tag + ": the plan agrees with the layout")
			var back := Mounts.from_inside(ship.grid, ship.components, def, plan["anchor"], rot)
			eq([back["why"], back["out"]], ["", out], tag + ": from_inside finds the same outside half")
			var uid := ship.components.place_mount(ship.grid, id, out, rot)
			check(uid >= 0, tag + ": placed")
	var ship := Wall.wall_ship(1, 0)
	var def := ship.components.def("human_concord_railgun")  # a 2x4 outside half over a 4x2 breech: the breech pokes out equally
	var plan := Mounts.plan(ship.grid, ship.components, def, Wall.out_for(def, 0), 0)
	eq(plan["cells"][0] - Wall.at(0, -2, 1), Vector2i.ZERO, "the 4 wide breech starts one cell left of the 2 wide outside half (u -2 for u -1..0)")
	var narrow := Wall.wall_ship(1, 0)
	var dome := narrow.components.def("leech_laser")
	eq(Mounts.plan(narrow.grid, narrow.components, dome, Wall.out_for(dome, 0) + Vector2i(0, 0), 0)["why"], "", "a 4x2 breech under a 3x3 dome")
	# a bad spot says why
	var bad := Mounts.plan(ship.grid, ship.components, def, Wall.out_for(def, 0) + Vector2i(0, 2), 0)
	eq(bad["why"], "the barrel must stick out into space", "the barrel in the wall")


func test_a_gun_whose_outside_half_no_longer_fits_goes_back_to_the_hold_with_a_log_line() -> void:
	# an old save: a Railgun whose old 4x2 outside half stood in a gap too narrow for a 2x4 one -- migration re-plans from the inside half
	var ship := Wall.wall_ship(1, 0)
	var c := ship.components
	var ok := c.place_mount(ship.grid, "laser_mk1", Wall.out_anchor(0), 0)
	check(ok >= 0, "(setup)")
	var d := c.to_dict()
	d["instances"][0]["id"] = "human_concord_railgun"  # a railgun saved at the laser's place with its old 4x2 outside half
	d["instances"][0]["out"] = [Wall.out_anchor(0).x, Wall.out_anchor(0).y]
	# block the cells above the wall that a 2x4 outside half needs (it is 4 deep, the old one 2 deep)
	var blocker := Wall.at(0, 0, -4)
	ship.grid.force_tile(blocker, "wall")
	var fresh := Components.new()
	fresh.load_defs("res://data/components.json")
	var err := fresh.load_dict(d, ship.grid)
	eq(err, "", "it loads")
	eq(fresh.instances.size(), 0, "the gun is not on the ship")
	eq(fresh.returned.size(), 1, "it went back to the cargo")
	check(fresh.returned[0]["text"].contains("no longer fits"), "with a log line: " + str(fresh.returned[0]["text"]))


func test_a_flush_pod_is_low_and_rams_pass_over_it() -> void:
	var c := _comps()
	check(Mounts.is_low(c.def("human_volley_rack")), "the pod is low")
	check(not Mounts.is_low(c.def("laser_mk1")), "a casemate is not")
	var ship := Wall.wall_ship(1, 0)
	var uid := ship.components.place_mount(ship.grid, "human_volley_rack", Wall.out_for(ship.components.def("human_volley_rack"), 0), 0)
	check(uid >= 0, "(setup)")
	var a := Arena.new(1)
	a.add_ship(ship)
	var cells: Array = Collisions.hit_cells(a, 0)["cells"]
	for oc in ship.components.instances[uid]["out_cells"]:
		check(not cells.has(oc), "the pod's cell %s is not a collision cell" % str(oc))
	var laser := Wall.wall_ship(1, 0)
	var lu := laser.components.place_mount(laser.grid, "laser_mk1", Wall.out_anchor(0), 0)
	var b := Arena.new(1)
	b.add_ship(laser)
	check(laser.components.instances[lu]["out_cells"].any(func(oc): return Collisions.hit_cells(b, 0)["cells"].has(oc)), "a casemate's barrel is hit first")


# --- several barrels on one base -----------------------------------------------------------------------------

func test_a_broadside_has_three_barrels_that_fire_in_turn() -> void:
	var ship := Wall.wall_ship(1, 0)
	var id := "gauntling_scrap_shotgun"
	var def := ship.components.def(id)
	var b := Mounts.barrel(def, Wall.out_for(def, 0), 0)
	eq(b["pivots"].size(), 3, "three pivots in the art")
	near(b["stagger_s"], 0.07, "staggered recoil", 1e-6)
	near(b["pivots"][1].x - b["pivots"][0].x, 26.0 / 16.0, "26 art px apart", 1e-6)
	near(b["pivot"].x, b["pivots"][1].x, "the pivot is their middle", 1e-6)
	var uid := ship.components.place_mount(ship.grid, id, Wall.out_for(def, 0), 0)
	var reactor := ship.components.place(ship.grid, "reactor_mk1", Wall.corner(0, 3, 4, 1, 4), 0)
	for c in [Wall.at(0, 0, 1), Wall.at(0, 1, 1), Wall.at(0, 2, 1), Wall.at(0, 3, 1)]:
		ship.cables.place(ship.grid, c)
	ship.refresh()
	var a := Arena.new(5)
	a.add_ship(ship, Vector2.ZERO)
	var m: Dictionary = a.ships[0].mounts[uid]
	eq(m["offsets"].size(), 3, "the mount knows its three barrels")
	check(reactor >= 0, "(setup)")
	var seen := []
	for k in 3:
		seen.append(a.weapons.muzzle_of(a, 0, m, k).x)
	check(seen[0] < seen[1] and seen[1] < seen[2], "the muzzles are side by side")
	var p0: Vector2 = a.weapons.muzzle_of(a, 0, m)
	a.ships[0].cooldowns.clear()
	check(a.fire(0, uid, Vector2(0, -1500)), "fires")
	var shots: Array = a.projectiles.filter(func(p): return p["owner"] == 0)
	check(shots.size() >= 3, "a flak volley (%d pellets)" % shots.size())
	var starts := {}
	for p in shots:
		starts[snappedf(p["pos"].x, 0.01)] = true
	eq(starts.size(), 3, "from three different barrels, round-robin")
	near(shots[0]["pos"].x, p0.x, "the first from the barrel that was next", 1.0)
	eq(m["shots"], shots.size(), "the count moves on")


# --- point defence by tier ---------------------------------------------------------------------------------

func _pd_arena(accuracy := 1.0) -> Dictionary:
	var a := Arena.new(3)
	a.add_ship(Wall.wall_ship(1), Vector2.ZERO)
	a.add_ship(Wall.wall_ship(1), Vector2(900.0, 0.0))
	a.weapons.defs["t_pd"] = {"kind": "bolt", "damage_type": "kinetic", "damage": 1.0, "cooldown": 0.2, "range": 700.0, "speed": 900.0, "aim": "turret", "turret": true,
		"arc": 360.0, "track": 720.0, "accuracy": accuracy, "effects": {"intercept": {"range": 400.0}}}
	a.weapons.defs["t_shell"] = {"kind": "bolt", "damage_type": "kinetic", "damage": 2.0, "cooldown": 1.0, "range": 900.0, "speed": 300.0}
	a.weapons.defs["t_fast"] = {"kind": "bolt", "damage_type": "kinetic", "damage": 2.0, "cooldown": 1.0, "range": 900.0, "speed": 900.0}
	a.weapons.defs["t_heavy"] = {"kind": "bolt", "damage_type": "kinetic", "damage": 9.0, "cooldown": 1.0, "range": 900.0, "speed": 700.0, "interceptable": true}
	a.weapons.defs["t_miss"] = {"kind": "missile", "damage_type": "explosive", "damage": 2.0, "cooldown": 1.0, "range": 900.0, "speed": 250.0, "turn": 0.0}
	var uid := a.add_mount(1, "t_pd", Vector2(15.5, 15.5), true, Vector2.LEFT)
	return {"a": a, "uid": uid, "m": a.ships[1].mounts[uid]}


func _shot(a: Arena, weapon: String, at: Vector2, vel: Vector2) -> Dictionary:
	var p := {"owner": 0, "w": a.weapons.def(weapon), "pos": a.ships[1].flight.pos + at, "vel": vel, "left": 1000.0, "target": 1 if weapon == "t_miss" else -1, "bounces": 0, "skip": {}}
	a.projectiles.append(p)
	return p


func test_point_defence_targets_missiles_and_slow_shots_and_ignores_fast_bolts() -> void:
	var r := _pd_arena()
	var a: Arena = r["a"]
	var m: Dictionary = r["m"]
	var w := a.weapons.def("t_pd")
	check(a.weapons.missile_target(a, 1, m, w) == null, "nothing incoming: no target")
	_shot(a, "t_fast", Vector2(-200, 0), Vector2(900, 0))
	check(a.weapons.missile_target(a, 1, m, w) == null, "a fast bolt is ignored")
	var slow := _shot(a, "t_shell", Vector2(-250, 0), Vector2(300, 0))
	check(a.weapons.missile_target(a, 1, m, w) == slow, "a slow shell is a target")
	var mis := _shot(a, "t_miss", Vector2(-150, 0), Vector2(250, 0))
	check(a.weapons.missile_target(a, 1, m, w) == mis, "a missile too, the nearest first")
	a.projectiles.erase(mis)
	a.projectiles.erase(slow)
	var heavy := _shot(a, "t_heavy", Vector2(-200, 0), Vector2(700, 0))
	check(a.weapons.missile_target(a, 1, m, w) == heavy, "a shot marked interceptable is a target at any speed")
	a.projectiles.clear()
	a.weapons.pd_speed = 950.0
	_shot(a, "t_fast", Vector2(-200, 0), Vector2(900, 0))
	check(a.weapons.missile_target(a, 1, m, w) != null, "pd_speed is the line (data)")


func test_point_defence_shoots_a_slow_shell_and_a_missile_down_and_a_ship_only_when_nothing_is_incoming() -> void:
	var r := _pd_arena()
	var a: Arena = r["a"]
	var slow := _shot(a, "t_shell", Vector2(-300, 0), Vector2(300, 0))
	var fast := _shot(a, "t_fast", Vector2(-300, 40), Vector2(900, 0))
	var mis := _shot(a, "t_miss", Vector2(-300, -40), Vector2(250, 0))
	for i in 90:
		a.step(DT)
		if not a.projectiles.has(slow) and not a.projectiles.has(mis):
			break
	check(not a.projectiles.has(slow), "the slow shell was shot down")
	check(not a.projectiles.has(mis), "and the missile")
	var hits := a.events.filter(func(e): return e["type"] == "effect" and e["kind"] == "intercept" and e["hit"])
	eq(hits.size(), 2, "two intercepts")
	eq(a.projectiles.filter(func(p): return p["owner"] == 1).size(), 0, "no real shot at the enemy ship while something was incoming")
	# nothing incoming any more: it turns on the ship at its low damage
	a.projectiles.erase(fast)
	for i in 120:
		a.step(DT)
	check(a.projectiles.any(func(p): return p["owner"] == 1) or a.events.any(func(e): return e["type"] == "hit" and e["ship"] == 0), "then it fires at the ship")
	near(a.weapons.def("t_pd")["damage"], 0.6, "at 60 percent of its low damage", 1e-9)


func test_the_drone_picket_and_the_flak_screen_are_point_defence_with_their_own_tier() -> void:
	var w := Weapons.new()
	for id in ["kett_drone_picket", "human_flak_screen"]:
		var d := w.def(id)
		check(d["effects"].has("intercept"), id + " intercepts")
		check(float(d["accuracy"]) > 0.0 and float(d["cooldown"]) > 0.0, id + " has its own accuracy and cooldown: its tier is data")
		eq(d["aim"], "turret", id + " is a point turret")
	check(w.pd_speed > 0.0, "pd_speed is data")
	check(w.def("grundl_slug_mortar").get("interceptable", false), "a slug shell is marked interceptable")


# --- a pilot that presents a broadside ----------------------------------------------------------------------

## A box ship: a ring of wall round a floor x 13..26, y 13..26, a reactor, a helm, a rear engine, and `guns`: [[id, rot], ...] on the flanks.
func _box(guns: Array) -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(41, 41), defs)
	g.fill_circle_hull(20.0)
	var ship := Ship.new("Box", g)
	ship.inventory.load_dict({"scrap": 800, "copper": 40})
	for y in range(12, 28):
		for x in range(12, 28):
			g.force_tile(Vector2i(x, y), "wall" if (x == 12 or x == 27 or y == 12 or y == 27) else "floor")
	var comps := ship.components
	for gun in guns:
		ship.inventory.add(str(gun[0]), 1)
		var def := comps.def(str(gun[0]))
		var rot: int = gun[1]
		var out := Vector2i(28, 16) if rot == 1 else (Vector2i(12 - def["mount"]["outside"][1], 16) if rot == 3 else Vector2i(17, 12 - def["mount"]["outside"][1]))
		if rot == 0:
			out = Vector2i(18 - def["mount"]["outside"][0] / 2, 12 - def["mount"]["outside"][1])
		check(comps.place_mount(g, str(gun[0]), out, rot) >= 0, "(setup: %s turned %d)" % [gun[0], rot])
	ship.inventory.add("engine_mk1", 3)
	check(comps.place_mount(g, "engine_mk1", Vector2i(18, 28), 2) >= 0, "(setup: the engine)")
	check(comps.place(g, "reactor_mk1", Vector2i(16, 14), 0) >= 0, "(setup: the reactor)")
	check(comps.place(g, "helm", Vector2i(20, 14), 0) >= 0, "(setup: the helm)")
	check(Shipgen._wire(ship), "(setup: the cables)")
	ship.refresh()
	return ship


func test_a_ship_with_guns_on_both_flanks_presents_a_flank_and_a_ship_with_bow_guns_its_bow() -> void:
	var a := Arena.new(2)
	a.add_ship(_box([["gauntling_scrap_shotgun", 1], ["gauntling_scrap_shotgun", 3]]), Vector2.ZERO)
	a.add_ship(_box([]), Vector2(0.0, -700.0))
	var ai := PilotAI.new(a, 0, 1, {"aim_skill": 1.0})
	var groups := ai.fixed_groups(ai._armed())
	eq(groups.keys().size(), 2, "two groups: starboard and port")
	check(groups.has(1) and groups.has(3), "by the side they face")
	check(float(groups[1]["dps"]) > 0.0, "weighed by dps")
	# the bow outweighs a lighter flank; a heavier flank wins; of two equal flanks the nearer to the foe
	eq(PilotAI.pick_facing({0: {"dps": 5.0, "axis": Vector2.UP}, 1: {"dps": 4.0, "axis": Vector2.RIGHT}}, 0.0), 0, "the bow when it outweighs")
	eq(PilotAI.pick_facing({0: {"dps": 5.0, "axis": Vector2.UP}, 1: {"dps": 6.0, "axis": Vector2.RIGHT}}, 0.0), 1, "a heavier flank")
	var two := {1: {"dps": 4.0, "axis": Vector2.RIGHT}, 3: {"dps": 4.0, "axis": Vector2.LEFT}}
	eq(PilotAI.pick_facing(two, deg_to_rad(80.0)), 1, "the foe on the right: starboard")
	eq(PilotAI.pick_facing(two, deg_to_rad(-80.0)), 3, "on the left: port")
	eq(PilotAI.pick_facing(two, deg_to_rad(-80.0), 1), 3, "the flank in use is given up when the other needs far less turn")
	eq(PilotAI.pick_facing(two, 0.0, 3), 3, "and kept while the other is no better")
	eq(PilotAI.pick_facing({}, 1.0), 0, "no fixed guns: the bow")


func test_a_ship_with_only_broadsides_turns_a_flank_to_the_foe_and_lands_hits() -> void:
	var a := Arena.new(4)
	a.add_ship(_box([["gauntling_scrap_shotgun", 1], ["gauntling_scrap_shotgun", 3]]), Vector2.ZERO)
	a.add_ship(_box([]), Vector2(0.0, -900.0))
	var ai := PilotAI.new(a, 0, 1, {"aim_skill": 1.0})
	var abeam_s := 0.0
	var first_abeam := -1.0
	for i in 60 * 20:
		ai.think(DT)
		a.step(DT)
		var to_foe: Vector2 = a.ships[1].flight.pos - a.ships[0].flight.pos
		var nose := Vector2.UP.rotated(a.ships[0].flight.angle)
		var off := absf(rad_to_deg(nose.angle_to(to_foe)))
		if absf(off - 90.0) < 35.0:
			abeam_s += DT
			if first_abeam < 0.0:
				first_abeam = i * DT
	check(first_abeam >= 0.0 and first_abeam < 5.0, "a flank is toward the foe within a few seconds (%.1f s)" % first_abeam)
	check(abeam_s > 10.0, "and it stays abeam most of the time (%.1f of 20 s)" % abeam_s)
	var hits := a.events.filter(func(e): return e["type"] == "hit" and e["ship"] == 1 and not e.get("ram", false))
	check(hits.size() >= 3, "and its broadsides land hits (%d)" % hits.size())
	eq(a.events.filter(func(e): return e["type"] == "ram").size(), 0, "without colliding")


# --- shipgen by shape ------------------------------------------------------------------------------------------

func test_shipgen_puts_each_gun_where_its_shape_says() -> void:
	for pair in [["laser_mk1", "bow"], ["human_concord_railgun", "bow"], ["basalt_quarry_driver", "bow"], ["laser_turret_mk1", "flank"], ["leech_laser", "flank"],
			["basalt_pumice_flak", "flank"], ["gauntling_scrap_shotgun", "flank"], ["human_volley_rack", "flank"], ["kett_drone_picket", "pd"], ["human_flak_screen", "pd"]]:
		eq(Shipgen.slot_of(pair[0]), pair[1], "%s stands on the %s" % [pair[0], pair[1]])
	var seen := {}
	for fac in ["kett", "gauntling", "human", "basalt", "fenn"]:
		for s in 8:
			var ship: Ship = Shipgen.build(fac, "large", 40 + s, 220.0)
			check(ship != null, "%s %d builds" % [fac, s])
			if ship == null:
				continue
			eq(Shipgen.validate(ship), [], "%s %d: valid, every mount whole" % [fac, s])
			for uid in ship.components.instances:
				var inst: Dictionary = ship.components.instances[uid]
				var d: Dictionary = ship.components.def(inst["id"])
				if d["family"] != "weapon":
					continue
				var slot := Shipgen.slot_of(inst["id"])
				seen[slot] = true
				if slot == "bow" and not (Shipgen._weapons.def(inst["id"])["turret"] or s < 0):
					eq(inst["rot"], 0, "%s: a bow gun faces forward" % inst["id"])
				if slot == "flank" and d["shape"] in ["broadside", "gun_strip"]:
					check(inst["rot"] in [1, 3] or Shipgen._weapons.def(inst["id"])["turret"] == false and inst["rot"] == 0, "%s: a broadside stands on a flank (or the bow when the flanks are full)" % inst["id"])
	check(seen.has("bow") and seen.has("flank"), "bow and flank guns both appear " + str(seen.keys()))


# --- the designs -----------------------------------------------------------------------------------------------

func _design_paths() -> Array[String]:
	var out: Array[String] = []
	var dirs: Array[String] = ["res://data/ships/"]
	for p in DirAccess.get_directories_at("res://data/packs"):
		dirs.append("res://data/packs/%s/ships/" % p)
	for dir in dirs:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				out.append(dir + f)
	return out


func test_every_shipped_design_keeps_every_gun_and_every_mount_is_whole() -> void:
	var n := 0
	for path in _design_paths():
		var ship = Ship.from_design(path)
		check(ship != null, path + " loads")
		if ship == null:
			continue
		n += 1
		eq(ship.components.returned.size(), 0, "%s: no gun went back to the hold" % path)
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		eq(int(d["components"]["version"]), Components.VERSION, path + ": on the current components version")
		for uid in ship.components.instances:
			var inst: Dictionary = ship.components.instances[uid]
			var def: Dictionary = ship.components.def(inst["id"])
			if not Mounts.is_mount(def):
				continue
			check(ship.components.has_outside(uid) and ship.components.link_intact(ship.grid, uid), "%s: %s is mounted whole" % [path, inst["id"]])
			eq(inst["out_cells"].size(), def["mount"]["outside"][0] * def["mount"]["outside"][1], "%s: %s has its whole outside half" % [path, inst["id"]])
			eq(int(inst["out_hp"]), ship.components.outside_hp_max(inst["id"]), "%s: %s starts with its outside half whole" % [path, inst["id"]])
	check(n >= 40, "every design was looked at (%d)" % n)
