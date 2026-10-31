extends "res://tests/base_test.gd"
## The trait keys race wave 2 needs (docs/waves/races_2_4.md; scripts/crew/traits.gd): `body` 1 (a small body that walks
## 1-wide crawlspaces), reveal_enemy, heat_speed, vacuum_walk, no_tools, hull_mend and station.evasion_add, one test each
## through the system it changes, plus the rig kinds of the drawer and the validators. Traits the data has no use for yet
## are made up in the library for the test (`_trait`) and removed again.

const Art = preload("res://scripts/view/art.gd")
const Content = preload("res://scripts/data/content.gd")
const CrewAbilities = preload("res://scripts/crew/crew_abilities.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const Schematic = preload("res://scripts/ui/schematic.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const TestContent = preload("res://tests/test_content.gd")

const STEP := 0.1
const FIXTURES := "res://tests/fixtures/art"


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, want, got])


func _trait(id: String, bag: Dictionary) -> void:
	var e := {"name": id}
	e.merge(bag)
	TraitSet.library()[id] = e


func _done() -> void:
	TraitSet.reset()
	Art.root = Art.DEFAULT_ROOT
	Art.clear_cache()


## A person on the body anchor (x, y), with the made-up traits `ids` worn (read again: gear does not change the body later).
func _person(p_name: String, x: int, y: int, ids: Array = [], player := false) -> CrewMember:
	var m := CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)))
	m.gear_traits = ids
	m.set_species("human")
	m.pos = Pathfinder.centre_of(Vector2i(x, y), m.body_size)
	m.is_player = player
	return m


## A small person (the trait body 1) on the cell (x, y).
func _small(p_name: String, x: int, y: int, player := false) -> CrewMember:
	_trait("t_tiny", {"body": 1})
	return _person(p_name, x, y, ["t_tiny"], player)


func _run(ship: Ship, jobs: Jobs, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-9:
		jobs.tick(ship, STEP)
		t += STEP


## Two 4x4 floors (x 2..5 and x 10..13, y 2..5) joined by a 1-wide corridor (y 3, x 6..9) between two walls: a
## crawlspace. A cell shot open in the wall at (8, 2) is next to the corridor and out of reach of a 2x2 body.
func _crawl_ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(20, 8), defs)
	for y in range(2, 6):
		for x in range(2, 6):
			g.force_tile(Vector2i(x, y), "floor")
		for x in range(10, 14):
			g.force_tile(Vector2i(x, y), "floor")
	for x in range(6, 10):
		g.force_tile(Vector2i(x, 3), "floor")
		g.force_tile(Vector2i(x, 2), "wall")
		g.force_tile(Vector2i(x, 4), "wall")
	var ship := Ship.new("Crawl", g)
	ship.refresh()
	return ship


## The sealed room of the fixture ship plus a second one under it (y 19..25), empty of air.
func _two_rooms() -> Ship:
	var ship := Fixture.room_ship()
	BuildSession.new(ship).apply(BuildSession.room_changes(Vector2i(8, 18), Vector2i(22, 26), "wall", "floor"))
	ship.refresh()
	for i in ship.atmosphere.pressure.size():
		ship.atmosphere.pressure[i] = 1.0
	return ship


# --- body 1 --------------------------------------------------------------------------------------------

func test_a_small_body_walks_a_one_wide_corridor_and_a_normal_body_does_not() -> void:
	var ship := _crawl_ship()
	var g: ShipGrid = ship.grid
	var from := Vector2i(2, 2)
	var to := Vector2i(12, 2)
	check(Pathfinder.find_path(g, from, to).is_empty(), "no 2x2 path through a 1-wide corridor")
	var path := Pathfinder.find_path(g, from, to, Callable(), 1)
	check(not path.is_empty(), "a 1x1 body has one")
	check(path.has(Vector2i(8, 3)), "through the corridor")
	eq(Pathfinder.anchor_of(Vector2(7.5, 3.5), 1), Vector2i(7, 3), "a small body's anchor is the cell it stands on")
	eq(Pathfinder.centre_of(Vector2i(7, 3), 1), Vector2(7.5, 3.5), "and its centre is the middle of that cell")
	eq(Pathfinder.anchor_of(Vector2(7, 4)), Vector2i(6, 3), "the default body is still 2x2")
	eq(Pathfinder.centre_of(Vector2i(6, 3)), Vector2(7, 4), "centred on the anchor + (1, 1)")
	eq(Pathfinder.body_cells(Vector2i(7, 3), 1), [Vector2i(7, 3)] as Array[Vector2i], "one cell")
	var big := _person("Big", 2, 2)
	var tiny := _small("Tiny", 2, 2)
	eq(big.body_size, 2, "a human is the normal 2x2")
	eq(tiny.body_size, 1, "the trait body 1 makes a small body")
	eq(tiny.body_cells().size(), 1, "which covers one cell")
	near(tiny.body_radius(), CrewMember.RADIUS / 2.0, "with half the radius")
	check(not big.go_to(g, to), "a normal crew member has no route to the other room")
	check(tiny.go_to(g, to), "a small one has")
	for i in 200:
		tiny.step(0.1)
	eq(tiny.pos, Pathfinder.centre_of(to, 1), "and walks it, ending on the centre of the last cell")
	eq(tiny.anchor(), to, "standing on it")
	# By hand: a small body slides through, a normal one stops at the mouth.
	var hand := _small("Hand", 5, 3, true)
	for i in 30:
		hand.move_input(g, Vector2.RIGHT, 0.1)
	check(hand.pos.x > 10.0, "a small player body walks through the crawlspace, x=%s" % hand.pos.x)
	var stuck := _person("Stuck", 4, 2, [], true)
	for i in 30:
		stuck.move_input(g, Vector2.RIGHT, 0.1)
	check(stuck.pos.x < 5.3, "a normal one stops at its mouth, x=%s" % stuck.pos.x)
	_done()


func test_the_body_is_the_smallest_of_the_traits_and_only_one_or_two() -> void:
	_trait("t_tiny", {"body": 1})
	_trait("t_wide", {"body": 2})
	near(TraitSet.of(CrewMember.new("X"))["body"], 2.0, "the default is 2x2")
	var m := CrewMember.new("X")
	m.gear_traits = ["t_wide", "t_tiny"]
	eq(TraitSet.of(m)["body"], 1, "the smallest wins")
	_trait("t_huge", {"body": 5})
	m.gear_traits = ["t_huge"]
	eq(TraitSet.of(m)["body"], 2, "nothing is bigger than 2x2 (the large rigs only draw bigger)")
	_done()


func test_a_small_crew_member_is_not_moved_out_of_a_crawlspace() -> void:
	var ship := _crawl_ship()
	var big := _person("Big", 2, 2)
	big.pos = Vector2(7.5, 3.5)  # in the corridor: wall cells under a 2x2 body
	var tiny := _small("Tiny", 7, 3)
	var other := _person("Other", 3, 2)  # fine where they are
	ship.crew.append_array([big, tiny, other])
	eq(ShipSim.relocate_crew(ship), 1, "only the normal body in the corridor is moved")
	eq(tiny.pos, Vector2(7.5, 3.5), "the small one stays in the crawlspace")
	check(big.fits(ship.grid, big.pos), "the normal one stands where a body fits")
	_done()


func test_a_small_crew_member_repairs_what_only_a_crawlspace_reaches() -> void:
	var done := {}
	for kind in ["small", "normal"]:
		var ship := _crawl_ship()
		ship.grid.breach(Vector2i(8, 2))  # the wall beside the corridor: only the corridor touches it
		ship.mark_dirty()
		ship.refresh()
		ship.crew.append(_small("Tiny", 3, 3) if kind == "small" else _person("Big", 3, 3))
		var jobs := Jobs.new()
		jobs.build_board(ship)
		var job: Dictionary = jobs.board["breach:8,2"]
		eq(jobs.stand_spots(ship, job).size(), 0, "no 2x2 body can stand beside it")
		check(jobs.stand_spots(ship, job, 1).has(Vector2i(8, 3)), "a 1x1 body can: in the corridor")
		_run(ship, jobs, 20.0)
		done[kind] = ship.grid.breached.is_empty()
	check(done["small"], "the small crew member walks in and seals the breach")
	check(not done["normal"], "a normal one cannot reach it")
	_done()


# --- reveal_enemy --------------------------------------------------------------------------------------

func test_reveal_enemy_shows_the_enemy_crew_while_the_reader_is_up() -> void:
	_trait("t_reader", {"reveal_enemy": true})
	var mine := Fixture.room_ship()
	var plain := _person("Plain", 11, 11)
	mine.crew.append(plain)
	check(not TraitSet.reveals_enemy(mine), "no reader aboard: nothing is revealed")
	var reader := _person("Oorth", 13, 13, ["t_reader"])
	mine.crew.append(reader)
	check(TraitSet.reveals_enemy(mine), "a reader aboard")
	reader.hurt(1000.0)
	check(not TraitSet.reveals_enemy(mine), "not while they are down")
	reader.heal(1000.0)
	check(TraitSet.reveals_enemy(mine), "and again when they are up")
	# What the panel draws: a mark per crew member of the enemy ship, at the cell position on its map.
	var theirs := Fixture.room_ship()
	var a := _person("A", 11, 11)
	var b := _person("B", 15, 12)
	b.hurt(1000.0)
	theirs.crew.append_array([a, b])
	var map := {"origin": Vector2(10.0, 20.0), "s": 8.0}
	var marks := Schematic.crew_marks(theirs, map)
	eq(marks.size(), 2, "one mark each")
	eq(marks[0]["at"], Vector2(10.0, 20.0) + a.pos * 8.0, "at their place on the map")
	check(not marks[0]["down"] and marks[1]["down"], "the down are marked")
	eq(Schematic.crew_marks(theirs, {}).size(), 0, "no map, no marks")
	var panel := Schematic.new()
	check(not panel.reveal, "a panel hides the crew until it is told")
	panel.free()
	_done()


# --- heat_speed ----------------------------------------------------------------------------------------

func test_heat_speed_scales_the_walk_with_the_heat_of_the_room() -> void:
	_trait("t_reptile", {"heat_speed": {"cold": 0.7, "hot": 1.2, "below": 20, "above": 50}})
	var ship := _two_rooms()
	var engine := Fixture.put(ship, "engine_mk1", 15, 10)
	var inst: Dictionary = ship.components.instances[engine]
	var drak := _person("Drak", 11, 11, ["t_reptile"], true)
	var plain := _person("Plain", 17, 14, [], true)
	var cold_room := _person("Cold", 12, 21, ["t_reptile"], true)  # the other room has no part: heat 0
	ship.crew.append_array([drak, plain, cold_room])
	var heats := {10.0: 0.7, 20.0: 1.0, 35.0: 1.0, 50.0: 1.0, 51.0: 1.2, 90.0: 1.2}
	for h in heats:
		inst["heat"] = h
		Jobs.new().tick(ship, 0.01)
		near(drak.speed_mod, heats[h], "at heat %s" % h)
		near(plain.speed_mod, 1.0, "a plain crew member never changes")
		near(cold_room.speed_mod, 0.7, "a room with no part is at heat 0: cold")
	inst["heat"] = 10.0
	Jobs.new().tick(ship, 0.01)
	var before := drak.pos
	drak.move_input(ship.grid, Vector2.RIGHT, 0.5)
	near(drak.pos.x - before.x, CrewMember.BASE_SPEED * 0.7 * 0.5, "the player's body walks 0.7 as fast in the cold", 1e-4)
	var npc := _person("Npc", 11, 14, ["t_reptile"])
	ship.crew.append(npc)
	Jobs.new().tick(ship, 0.01)
	npc.path = [Vector2i(17, 14)]
	var start := npc.pos
	npc.step(0.5)
	near(npc.pos.x - start.x, CrewMember.BASE_SPEED * 0.7 * 0.5, "so does a crew member on a path", 1e-4)
	near(TraitSet.heat_factor(TraitSet.of(plain), 90.0), 1.0, "no heat_speed: 1")
	_done()


# --- vacuum_walk ---------------------------------------------------------------------------------------

func test_vacuum_walk_does_not_suffocate() -> void:
	_trait("t_void", {"vacuum_walk": true})
	var ship := _two_rooms()
	var room := ship.atmosphere.room_at(Vector2i(12, 22))
	ship.atmosphere.pressure[room] = 0.0
	var walker := _person("Void", 11, 21, ["t_void"], true)
	var plain := _person("Plain", 16, 21, [], true)
	ship.crew.append_array([walker, plain])
	var jobs := Jobs.new()
	_run(ship, jobs, 2.0)
	near(plain.hp, 100.0 - 2.0 * 5.0, "a plain crew member suffocates (5 hp a second)", 1e-3)
	near(walker.hp, 100.0, "a vacuum walker takes nothing from the empty room")
	near(TraitSet.of(walker)["o2_use"], 1.0, "they still breathe unless o2_use says 0")
	check(TraitSet.of(walker)["vacuum_walk"] and not TraitSet.of(plain)["vacuum_walk"], "the flag is theirs alone")
	_done()


# --- no_tools ------------------------------------------------------------------------------------------

func test_no_tools_takes_no_repair_or_extinguish_jobs() -> void:
	_trait("t_handless", {"no_tools": true})
	var ship := Fixture.room_ship()
	ship.fires[Vector2i(15, 12)] = 0.5
	var helm := Fixture.put(ship, "helm", 12, 10)
	var engine := Fixture.put(ship, "engine_mk1", 17, 10)
	ship.components.instances[engine]["status"] = "disabled"  # a repair job
	ship.grid.breach(Vector2i(15, 8))
	ship.mark_dirty()
	ship.refresh()
	var wisp := _person("Wisp", 11, 13, ["t_handless"])
	ship.crew.append(wisp)
	var jobs := Jobs.new()
	jobs.build_board(ship)
	var types := jobs.board.values().map(func(j): return j["type"])
	for t in ["extinguish", "repair_breach", "repair_component", "man_station"]:
		check(types.has(t), "the board has a %s job" % t)
	jobs.assign(ship)
	eq(wisp.job.get("type", ""), "man_station", "the only job they take is a post: the helm")
	check(not Jobs.TOOL_JOBS.has("man_station") and not Jobs.TOOL_JOBS.has("revive"), "posts and reviving are not tool work")
	var hand := Jobs.new()
	hand.build_board(ship)
	var fire_at := _person("Hand", 14, 12, ["t_handless"], true)
	ship.crew.append(fire_at)
	eq(hand.hand_work(ship, fire_at, 0.5), "", "nor does the player's hand work what is beside them")
	near(float(ship.fires[Vector2i(15, 12)]), 0.5, "the fire is untouched")
	var plain := _person("Plain", 14, 12, [], true)
	ship.crew.append(plain)
	check(hand.hand_work(ship, plain, 0.5) != "", "a plain player does")
	ship.crew.erase(plain)
	ship.crew.erase(fire_at)
	eq(jobs.order_repair(ship, engine), "no crew to send", "and a repair order finds nobody to send")
	var other := Fixture.room_ship()
	other.crew.append(_person("Plain", 11, 13))
	var engine2 := Fixture.put(other, "engine_mk1", 17, 10)
	other.components.instances[engine2]["status"] = "disabled"
	other.refresh()
	var j2 := Jobs.new()
	j2.build_board(other)
	j2.assign(other)
	eq(other.crew[0].job.get("type", ""), "repair_component", "a plain crew member takes the repair")
	_done()


# --- hull_mend -----------------------------------------------------------------------------------------

func test_hull_mend_repairs_adjacent_walls_and_seals_breaches_when_idle() -> void:
	_trait("t_barnacle", {"hull_mend": {"rate": 1.0, "seal": 8.0}})
	var ship := Fixture.room_ship()
	var west := Vector2i(8, 10)  # the wall beside a body on anchor (9, 10)
	var far := Vector2i(8, 14)
	var top := ship.grid.max_hp_of(west)
	ship.grid.hp[west] = top - 3.0
	ship.grid.hp[far] = top - 3.0
	var m := _person("Hull", 9, 10, ["t_barnacle"])
	m.hold = 1000.0  # idle: the board leaves them alone
	ship.crew.append(m)
	var jobs := Jobs.new()
	_run(ship, jobs, 2.0)
	near(float(ship.grid.hp[west]), top - 1.0, "the wall beside them gains rate hp a second", 1e-3)
	near(float(ship.grid.hp[far]), top - 3.0, "one that is not beside them does not")
	_run(ship, jobs, 5.0)
	check(not ship.grid.hp.has(west), "fully mended: the cell is not listed (full hp)")
	near(ship.grid.hp_of(west), top, "at its full hp")
	var other := Vector2i(8, 11)
	ship.grid.hp[west] = top - 0.5
	ship.grid.hp[other] = top - 5.0
	_run(ship, jobs, 1.0)
	check(not ship.grid.hp.has(west), "the rate is one budget for all the walls beside them: the first cell is full")
	near(float(ship.grid.hp[other]), top - 4.5, "and the rest goes to the next", 1e-3)
	# A breach beside them is sealed after `seal` seconds.
	ship.grid.breach(west)
	ship.mark_dirty()
	ship.refresh()
	_run(ship, jobs, 7.5)
	check(ship.grid.breached.has(west), "not yet after 7.5 s")
	_run(ship, jobs, 1.0)
	check(not ship.grid.breached.has(west) and ship.grid.get_tile(west) != "", "sealed after 8 s: the wall is back")
	# Without the trait nothing mends.
	var plain_ship := Fixture.room_ship()
	plain_ship.grid.hp[west] = top - 3.0
	var p := _person("Plain", 9, 10)
	p.hold = 1000.0
	plain_ship.crew.append(p)
	_run(plain_ship, Jobs.new(), 3.0)
	near(float(plain_ship.grid.hp[west]), top - 3.0, "a plain crew member mends nothing")
	# seal 0 cannot seal; rate 0 cannot mend.
	_trait("t_rate_only", {"hull_mend": {"rate": 1.0}})
	var ship2 := Fixture.room_ship()
	ship2.grid.breach(west)
	ship2.mark_dirty()
	ship2.refresh()
	var q := _person("Rate", 9, 10, ["t_rate_only"])
	q.hold = 1000.0
	ship2.crew.append(q)
	_run(ship2, Jobs.new(), 30.0)
	check(ship2.grid.breached.has(west), "with no seal time a breach stays")
	_done()


# --- station.evasion_add -------------------------------------------------------------------------------

func test_station_evasion_add_is_added_at_the_helm() -> void:
	_trait("t_pilot", {"station": {"evasion_add": 0.05}})
	_trait("t_gunner", {"work_mult": {"man": 2.0}})
	var ship := Fixture.room_ship()
	var helm := Fixture.put(ship, "helm", 12, 10)
	var gun := Fixture.put(ship, "laser_mk1", 15, 10)
	var ada := _person("Ada", 12, 13)
	ship.crew.append(ada)
	ship.manned[helm] = "Ada"
	var base: float = CrewMember.config()["manned"]["helm_evasion"]
	near(Jobs.evasion_bonus(ship), base, "a plain operator: the post's own evasion")
	ada.gear_traits = ["t_pilot"]
	near(Jobs.evasion_bonus(ship), base + 0.05, "a Lantern pilot adds 0.05")
	ada.gear_traits = ["t_pilot", "t_gunner"]
	near(Jobs.evasion_bonus(ship), base * 2.0 + 0.05, "it is flat: not scaled by how well they man the post")
	ada.hurt(1000.0)
	near(Jobs.evasion_bonus(ship), base, "a downed operator adds none of their own: only the post's evasion")
	ada.heal(1000.0)
	ship.manned.clear()
	ship.manned[gun] = "Ada"
	near(Jobs.evasion_bonus(ship), 0.0, "at a weapon it adds no evasion")
	near(TraitSet.helm_evasion_add(ship, helm), 0.0, "nobody at the helm: 0")
	_done()


# --- the keys merge ------------------------------------------------------------------------------------

func test_the_wave_2_keys_merge_and_default() -> void:
	var plain := TraitSet.of(CrewMember.new("X"))
	check(not plain["reveal_enemy"] and not plain["vacuum_walk"] and not plain["no_tools"], "the flags default to false")
	near(plain["heat_speed"]["cold"], 1.0, "heat_speed defaults to no change")
	near(plain["hull_mend"]["rate"], 0.0, "no mending")
	near(plain["station"]["evasion_add"], 0.0, "no evasion")
	_trait("t_a", {"heat_speed": {"cold": 0.5, "hot": 2.0, "below": 10, "above": 80}, "hull_mend": {"rate": 0.5, "seal": 10}, "station": {"evasion_add": 0.02}})
	_trait("t_b", {"heat_speed": {"cold": 0.5, "below": 30, "above": 60}, "hull_mend": {"rate": 0.25, "seal": 4}, "station": {"evasion_add": 0.03}, "no_tools": true})
	_trait("t_c", {"hull_mend": {"rate": 1.0}})
	var m := CrewMember.new("X")
	m.gear_traits = ["t_a", "t_b", "t_c"]
	var t := TraitSet.of(m)
	near(t["heat_speed"]["cold"], 0.25, "cold factors multiply")
	near(t["heat_speed"]["hot"], 2.0, "hot too")
	near(t["heat_speed"]["below"], 30.0, "the cold zone is the widest")
	near(t["heat_speed"]["above"], 60.0, "and so is the hot one")
	near(t["hull_mend"]["rate"], 1.75, "mending rates add")
	near(t["hull_mend"]["seal"], 4.0, "the quickest seal wins, and 0 means none")
	near(t["station"]["evasion_add"], 0.05, "evasion adds")
	check(t["no_tools"], "a flag is true if any trait says so")
	_done()


# --- the validators ------------------------------------------------------------------------------------

func test_the_validators_know_the_wave_2_keys() -> void:
	var good := [
		{"id": "a", "name": "A", "body": 1, "reveal_enemy": true, "vacuum_walk": true, "no_tools": true},
		{"id": "b", "name": "B", "heat_speed": {"cold": 0.7, "hot": 1.2, "below": 20, "above": 50}, "hull_mend": {"rate": 1.0, "seal": 8.0}, "station": {"evasion_add": 0.05}},
	]
	var checker = TestContent.new()
	eq(checker.trait_problems(good), [] as Array[String], "well-formed wave 2 traits pass")
	var bad := [
		{"id": "c", "name": "C", "body": 3},
		{"id": "d", "name": "D", "vacuum_walk": 1},
		{"id": "e", "name": "E", "no_tools": "yes"},
		{"id": "f", "name": "F", "heat_speed": {"cold": 0.7, "sideways": 1}},
		{"id": "g", "name": "G", "hull_mend": {"rate": "fast"}},
		{"id": "h", "name": "H", "heat_speed": 0.7},
		{"id": "i", "name": "I", "see_through_walls": true},
		{"id": "j", "name": "J", "body": "small"},
	]
	var problems: Array[String] = checker.trait_problems(bad)
	eq(problems.size(), 8, "each bad trait is one problem: %s" % str(problems))
	for t in ["body", "vacuum_walk", "no_tools", "sideways", "rate", "heat_speed", "see_through_walls"]:
		check(problems.any(func(p): return p.contains(t)), "a problem names " + t)
	var chars: Array[String] = CrewAbilities._traits_problems("x", {"body": 3, "vacuum_walk": 1, "hull_mend": {"rate": "x"}, "bogus": 1})
	eq(chars.size(), 4, "a character's own trait keys are checked the same way: %s" % str(chars))
	eq(CrewAbilities._traits_problems("x", {"body": 1, "no_tools": true, "heat_speed": {"cold": 0.5}}), [] as Array[String], "and pass when well formed")
	_done()


# --- rigs ----------------------------------------------------------------------------------------------

func test_a_floating_rig_has_no_walk_cycle_and_bobs() -> void:
	Art.root = FIXTURES
	Art.tier_fallback = true
	Art.clear_cache()
	var sheet = Art.crew("floater")
	eq(PersonDrawer.rig_kind(sheet), "floating", "crew.json says what kind of rig it is")
	eq(PersonDrawer.rig_kind(Art.crew("human")), "normal", "and a rig that says nothing is normal")
	var legs := func(pose: Dictionary) -> int:
		for l in PersonDrawer.plan(sheet, pose):
			if l["layer"] == "legs":
				return l["frame"]
		return -1
	eq(legs.call({"moving": true, "phase": TAU * 0.4}), 0, "walking: no walk cycle, the tail plays `float` (frame 0 at t = 0)")
	eq(legs.call({"moving": true, "phase": TAU * 0.4, "t": 0.2}), 1, "float runs by time (6 fps)")
	eq(legs.call({"moving": false, "t": 0.4}), 2, "walking or not")
	eq(legs.call({"moving": false, "t": 0.5}), 0, "and loops")
	eq(legs.call({"moving": true, "down": true, "t": 0.2}), 6, "lying down: the stand frame")
	var human_legs := PersonDrawer.plan(Art.crew("human"), {"moving": true, "phase": TAU * 0.4})
	eq(human_legs[0]["frame"], 2, "while a normal rig still walks")
	check(absf(PersonDrawer.bob({"t": 0.0})) < 1e-6 and absf(PersonDrawer.bob({"t": 0.5 * PI / PersonDrawer.BOB_RATE}) - PersonDrawer.BOB) < 1e-6, "the bob is a sine of time, BOB source px high")
	near(PersonDrawer.bob({"t": 1.0, "down": true}), 0.0, "no bob while down")
	# Drawn: the body is lifted by the bob and the shadow sits further away than a normal figure's.
	var canvas = load("res://tests/test_person_art.gd").FakeCanvas.new()
	var pose := {"species": "floater", "t": 0.5 * PI / PersonDrawer.BOB_RATE}
	PersonDrawer.draw(canvas, Vector2(100, 100), pose, {}, 32.0)
	var moves: Array = canvas.calls.filter(func(c): return c["op"] == "transform" and c["scale"] != Vector2.ONE)
	eq(moves[0]["pos"], Vector2(100, 100) + Vector2(2, 2) * (1.0 + PersonDrawer.HOVER), "the shadow of a floating body")
	near(moves[-1]["pos"].y, 100.0 - PersonDrawer.BOB * 2.0, "the body rides up by the bob (2 px per source px)")
	near(moves[-1]["pos"].x, 100.0, "and only up")
	var plain = load("res://tests/test_person_art.gd").FakeCanvas.new()
	PersonDrawer.draw(plain, Vector2(100, 100), {"species": "human", "t": 0.5 * PI / PersonDrawer.BOB_RATE}, {}, 32.0)
	var shadow: Array = plain.calls.filter(func(c): return c["op"] == "transform" and c["scale"] != Vector2.ONE)
	eq(shadow[0]["pos"], Vector2(102, 102), "a normal figure keeps its one-px shadow")
	eq(shadow[-1]["pos"], Vector2(100, 100), "and does not bob")
	_done()


func test_every_shipped_rig_has_the_frame_of_its_kind() -> void:
	var seen := 0
	for dir in DirAccess.get_directories_at("res://art/crew"):
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://art/crew/%s/crew.json" % dir))
		if not d is Dictionary:
			continue
		var kind := str(d.get("kind", "normal" if d["frame"][0] == 33 else "large"))  # grundl, the first large rig, names none
		check(PersonDrawer.RIGS.has(kind), "%s: kind '%s' is one of %s" % [dir, kind, ", ".join(PersonDrawer.RIGS.keys())])
		if not PersonDrawer.RIGS.has(kind):
			continue
		var size: int = PersonDrawer.RIGS[kind][0]
		var pivot: int = PersonDrawer.RIGS[kind][1]
		eq([int(d["frame"][0]), int(d["frame"][1])], [size, size], "%s: a %s rig's frame (art/README.md)" % [dir, kind])
		eq([int(d["pivot"][0]), int(d["pivot"][1])], [pivot, pivot], "%s: and its pivot" % dir)
		seen += 1
	check(seen >= 10, "found the shipped rigs (%d)" % seen)
	eq(PersonDrawer.RIGS.keys().size(), 4, "four kinds: normal, large, small, floating")
