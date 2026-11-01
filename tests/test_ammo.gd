extends "res://tests/base_test.gd"
## Ammo racks, the restock job and the rack explosion (docs/CONTENT.md 4f; scripts/sim/ammo.gd). Belts are in test_belts.gd.

const Fx = preload("res://tests/fixture_ammo.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Damage = preload("res://scripts/combat/damage.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Components = preload("res://scripts/ship/components.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Stats = preload("res://scripts/sim/stats.gd")


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _why(a, uid: int) -> String:
	return a.weapons.can_fire(a, 0, uid, Fx.AIM)


## A crew member whose 2x2 body has its top-left cell on (x, y).
func _person(x: int, y: int, species := "human") -> CrewMember:
	return CrewMember.new("Hand", Pathfinder.centre_of(Vector2i(x, y)), species)


# --- the data -------------------------------------------------------------------------------------------

func test_the_rack_and_the_three_drives_are_in_the_data() -> void:
	var ship := Ship.new_starter()
	var rack: Dictionary = ship.components.def("ammo_rack")
	eq(rack["size"], [2, 2], "a rack is 2x2")
	eq(rack["family"], "ammo_rack", "its family")
	eq(rack["stats"]["capacity"], 20, "it holds 20 units")
	check(ship.crafting.is_known("ammo_rack"), "the rack is a starting blueprint")
	var table := {"belt_drive_scrap": ["scrap", 3.0, 0.8], "belt_drive_std": ["standard", 5.0, 0.5], "belt_drive_neon": ["neon", 8.0, 0.3]}
	for id in table:
		var d: Dictionary = ship.components.def(id)
		eq(d["size"], [2, 2], id + " is 2x2")
		eq(d["line"], table[id][0], id + ": its line")
		eq(d["stats"]["belt_speed"], table[id][1], id + ": cells a second")
		eq(d["stats"]["belt_interval"], table[id][2], id + ": seconds a unit")
		eq(ship.effective(id)["power"] < 0, true, id + " draws power")
		check(not ship.crafting.is_known(id), id + " is not a starting blueprint")
	near(float(ship.effective("belt_drive_std")["power"]), -1.0, "the Autoloader draws 1")
	check(Ammo.explosive("missile") and not Ammo.explosive("scrap"), "missiles explode, scrap does not")


# --- who a gun draws from -----------------------------------------------------------------------------------

func test_a_ship_with_no_rack_still_fires_from_the_cargo() -> void:
	var d := Fx.room()
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	check(not Ammo.uses_racks(ship), "no racks aboard")
	eq(_why(a, d["gun"]), "no ammo", "no missiles in the cargo")
	ship.inventory.add("missile", 2)
	eq(_why(a, d["gun"]), "", "missiles in the cargo: it fires, as it always did")
	check(a.fire(0, d["gun"], Fx.AIM), "it fires")
	eq(ship.inventory.count("missile"), 1, "one missile came out of the cargo")


func test_a_virtual_test_weapon_draws_from_the_cargo_even_on_a_ship_with_racks() -> void:
	var d := Fx.with_rack()
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	var virt := a.add_mount(0, "artemis_mk1", Vector2(15.5, 17.5))
	ship.inventory.add("missile", 1)
	eq(_why(a, virt), "", "a virtual mount has no inside half: the cargo feeds it")


func test_a_gun_draws_from_a_rack_in_its_room_and_not_from_the_cargo() -> void:
	var d := Fx.with_rack()
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	ship.inventory.add("missile", 9)
	check(Ammo.uses_racks(ship), "a rack aboard: the guns draw from racks")
	eq(_why(a, d["gun"]), "rack empty", "the rack in its room is empty: the cargo does not count")
	Fx.stock(ship, d["rack"], "missile", 2)
	eq(_why(a, d["gun"]), "", "two missiles in the rack")
	check(a.fire(0, d["gun"], Fx.AIM), "it fires")
	eq(Ammo.count_in(ship, d["rack"]), 1, "one unit left the rack")
	eq(ship.inventory.count("missile"), 9, "and none the cargo")
	a.ships[0].cooldowns.erase(d["gun"])
	check(a.fire(0, d["gun"], Fx.AIM), "the second shot")
	a.ships[0].cooldowns.erase(d["gun"])
	eq(_why(a, d["gun"]), "rack empty", "empty again")


func test_a_rack_holding_the_wrong_ammo_is_empty_for_the_gun() -> void:
	var d := Fx.with_rack()
	var a := Fx.arena(d["ship"])
	Fx.stock(d["ship"], d["rack"], "scrap", 10)
	eq(_why(a, d["gun"]), "rack empty", "scrap is no use to an Artemis")


func test_a_rack_in_another_room_is_out_of_reach() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	ship.belts.cells.clear()  # no belt: the rack in the west room is not on any network
	ship.belts.rev += 1
	var a := Fx.arena(ship)
	Fx.stock(ship, d["rack"], "missile", 10)
	eq(_why(a, d["gun"]), "no ammo rack in reach", "full, but in another room and on no belt")


func test_a_disabled_rack_is_out_of_reach_until_repaired() -> void:
	var d := Fx.with_rack()
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	Fx.stock(ship, d["rack"], "missile", 5)
	ship.components.instances[d["rack"]]["status"] = "disabled"
	eq(_why(a, d["gun"]), "no ammo rack in reach", "a disabled rack gives nothing")
	ship.repair(d["rack"])
	eq(_why(a, d["gun"]), "", "mended")


func test_a_rack_is_one_of_many_and_the_guns_spend_from_the_rooms_racks_in_order() -> void:
	var d := Fx.with_rack()
	var ship: Ship = d["ship"]
	var second: int = ship.components.place(ship.grid, "ammo_rack", Vector2i(18, 20), 0)
	Fx.stock(ship, d["rack"], "missile", 1)
	Fx.stock(ship, second, "missile", 1)
	var a := Fx.arena(ship)
	check(a.fire(0, d["gun"], Fx.AIM), "first shot")
	a.ships[0].cooldowns.erase(d["gun"])
	check(a.fire(0, d["gun"], Fx.AIM), "second shot, from the other rack")
	eq(Ammo.count_in(ship, d["rack"]) + Ammo.count_in(ship, second), 0, "both are empty")


func test_ammo_mult_costs_whole_units_from_the_rack() -> void:
	var d := Fx.with_rack("grundl_slug_mortar")
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	Fx.stock(ship, d["rack"], "scrap", 7)
	check(a.fire(0, d["gun"], Fx.AIM), "the Slug Mortar fires")
	eq(Ammo.count_in(ship, d["rack"]), 4, "three scrap a shot")
	a.ships[0].cooldowns.erase(d["gun"])
	check(a.fire(0, d["gun"], Fx.AIM), "again")
	a.ships[0].cooldowns.erase(d["gun"])
	eq(_why(a, d["gun"]), "rack empty", "one scrap left, three needed")


func test_the_cargo_deck_doubles_the_capacity_of_the_racks_in_its_room() -> void:
	var d := Fx.with_rack()
	var ship: Ship = d["ship"]
	eq(Ammo.capacity(ship, d["rack"]), 20, "20 units")
	ship.inventory.add("grundl_cargo_deck", 1)
	var deck: int = ship.components.place(ship.grid, "grundl_cargo_deck", Vector2i(9, 16), 0)
	ship.refresh()
	check(deck >= 0, "the deck fits")
	eq(Ammo.capacity(ship, d["rack"]), 40, "twice, in its room")


# --- restock ------------------------------------------------------------------------------------------------

func test_a_rack_below_half_gets_a_restock_job_at_priority_40() -> void:
	var d := Fx.with_rack()
	var ship: Ship = d["ship"]
	var jobs := Jobs.new()
	ship.inventory.add("missile", 30)
	Fx.stock(ship, d["rack"], "missile", 9)
	jobs.build_board(ship)
	check(jobs.board.has("stock:%d" % d["rack"]), "9 of 20 is below half: a job")
	eq(jobs.board["stock:%d" % d["rack"]]["priority"], 40, "priority 40")
	Fx.stock(ship, d["rack"], "missile", 10)
	jobs.build_board(ship)
	check(not jobs.board.has("stock:%d" % d["rack"]), "10 of 20 is half: no job")
	Fx.stock(ship, d["rack"], "missile", 3)
	ship.inventory.add("missile", -30)
	jobs.build_board(ship)
	check(not jobs.board.has("stock:%d" % d["rack"]), "nothing in the cargo to carry: no job")


func test_an_empty_rack_is_stocked_with_what_the_guns_in_reach_spend() -> void:
	var d := Fx.with_rack("grundl_slug_mortar")
	var ship: Ship = d["ship"]
	ship.inventory.add("missile", 10)
	ship.inventory.add("scrap", -ship.inventory.count("scrap"))
	eq(Ammo.wanted_item(ship, d["rack"]), "", "the Slug Mortar wants scrap and there is none: not missiles")
	ship.inventory.add("scrap", 5)
	eq(Ammo.wanted_item(ship, d["rack"]), "scrap", "scrap")
	Fx.stock(ship, d["rack"], "missile", 4)
	eq(Ammo.wanted_item(ship, d["rack"]), "missile", "a rack that holds something is topped up with it")


func test_restocking_carries_five_units_a_second_and_a_grundl_ten() -> void:
	var d := Fx.with_rack()
	var ship: Ship = d["ship"]
	ship.inventory.add("missile", 100)
	var jobs := Jobs.new()
	jobs.build_board(ship)
	var job: Dictionary = jobs.board["stock:%d" % d["rack"]]
	var human := _person(20, 18)  # beside the rack at (20, 20)
	check(jobs.in_reach(human, job), "the crew member stands next to the rack")
	jobs.work(ship, human, job, 1.0)
	eq(Ammo.count_in(ship, d["rack"]), 5, "one second: 5 units")
	eq(ship.inventory.count("missile"), 95, "out of the cargo")
	jobs.work(ship, human, job, 0.4)
	eq(Ammo.count_in(ship, d["rack"]), 7, "1.4 s: 7 units")
	var d2 := Fx.with_rack()
	var s2: Ship = d2["ship"]
	s2.inventory.add("missile", 100)
	var j2 := Jobs.new()
	j2.build_board(s2)
	var grundl := _person(20, 18, "grundl")
	j2.work(s2, grundl, j2.board["stock:%d" % d2["rack"]], 1.0)
	eq(Ammo.count_in(s2, d2["rack"]), 10, "a Grundl (restock x2): 10 units in a second")


func test_a_crew_member_fills_the_rack_to_the_top_not_to_half() -> void:
	var d := Fx.with_rack()
	var ship: Ship = d["ship"]
	ship.inventory.add("missile", 100)
	Fx.stock(ship, d["rack"], "missile", 4)
	var jobs := Jobs.new()
	jobs.build_board(ship)
	var human := _person(20, 18)
	jobs.work(ship, human, jobs.board["stock:%d" % d["rack"]], 2.1)  # 10 units: 14, past half
	eq(Ammo.count_in(ship, d["rack"]), 14, "14 units")
	jobs.build_board(ship)
	check(jobs.board.has("stock:%d" % d["rack"]), "the job stays on the board: someone is filling it")
	jobs.work(ship, human, jobs.board["stock:%d" % d["rack"]], 5.0)
	eq(Ammo.count_in(ship, d["rack"]), 20, "full")
	check(not jobs.board.has("stock:%d" % d["rack"]), "and the job is done")
	eq(ship.inventory.count("missile"), 100 - 16, "16 carried")


func test_crew_walk_to_the_rack_and_restock_it_on_their_own() -> void:
	var d := Fx.with_rack()
	var ship: Ship = d["ship"]
	ship.inventory.add("missile", 40)
	var gunner := _person(10, 18)  # the gun is manned: the first to be free takes its post (priority 50)
	var hand := _person(10, 20)
	hand.name = "Second"
	ship.crew.append_array([gunner, hand])
	var jobs := Jobs.new()
	var worked := false
	for i in 400:
		jobs.tick(ship, 0.1)
		worked = worked or str(hand.job.get("type", gunner.job.get("type", ""))) == "restock" or hand.job.get("type", "") == "restock" or gunner.job.get("type", "") == "restock"
	check(worked, "somebody took the restock job")
	eq(Ammo.count_in(ship, d["rack"]), 20, "the crew filled the rack in 40 s")
	eq(ship.inventory.count("missile"), 20, "from the cargo")


# --- the explosion ---------------------------------------------------------------------------------------------

func test_a_wrecked_rack_of_missiles_blows_up_its_room_and_a_rack_of_scrap_does_not() -> void:
	var d := Fx.with_rack()
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	Fx.stock(ship, d["rack"], "missile", 5)  # 10 damage
	var before: float = ship.components.instances[d["reactor"]]["hp"]
	Damage.wreck_part(a, 0, d["rack"])
	check(not ship.components.instances.has(d["rack"]), "the rack is gone")
	eq(a.events.filter(func(e): return e["type"] == "rack_blast").size(), 1, "a rack_blast event")
	var gun: Dictionary = ship.components.instances[d["gun"]]
	eq(gun["status"], "disabled", "10 damage disables the gun in the room (hp %d)" % gun["hp"])
	eq(ship.components.instances[d["reactor"]]["status"], "disabled", "and the reactor")
	check(float(ship.components.instances[d["reactor"]]["hp"]) < before, "which lost hp")
	# scrap does not explode
	var d2 := Fx.with_rack()
	var a2 := Fx.arena(d2["ship"])
	Fx.stock(d2["ship"], d2["rack"], "scrap", 20)
	Damage.wreck_part(a2, 0, d2["rack"])
	eq(a2.events.filter(func(e): return e["type"] == "rack_blast").size(), 0, "no blast for scrap")
	eq(d2["ship"].components.instances[d2["gun"]]["status"], "ok", "the gun is fine")
	# an empty rack does not either
	var d3 := Fx.with_rack()
	var a3 := Fx.arena(d3["ship"])
	Damage.wreck_part(a3, 0, d3["rack"])
	eq(a3.events.filter(func(e): return e["type"] == "rack_blast").size(), 0, "no blast for an empty rack")


func test_the_blast_is_two_damage_a_unit_and_stays_in_its_room() -> void:
	var d := Fx.belts()  # the rack is in the west room; the gun and the reactor in the east room
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	Fx.stock(ship, d["rack"], "missile", 2)  # 4 damage
	var wall_before: float = ship.grid.hp_of(Vector2i(12, 16))
	Damage.wreck_part(a, 0, d["rack"])
	near(ship.grid.hp_of(Vector2i(12, 16)), wall_before - 4.0 if wall_before > 4.0 else 0.0, "the wall round the room took 4")
	eq(ship.components.instances[d["gun"]]["status"], "ok", "the gun in the other room was spared")
	var blast := Ammo.blast(Fx.with_rack()["ship"], -1)
	eq(blast, {}, "no such rack: no blast")


func test_a_blast_that_breaches_the_wall_lets_the_air_out() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	Fx.stock(ship, d["rack"], "missile", 10)  # 20 damage: every wall round the west room goes
	Damage.wreck_part(a, 0, d["rack"])
	check(ship.grid.breached.has(Vector2i(12, 16)), "the dividing wall is breached")
	check(a.events.any(func(e): return e["type"] == "breach"), "a breach event")


# --- saving -----------------------------------------------------------------------------------------------------

func test_rack_contents_and_loaded_units_survive_a_save() -> void:
	var d := Fx.with_rack()
	var ship: Ship = d["ship"]
	Fx.stock(ship, d["rack"], "missile", 13)
	ship.components.instances[d["gun"]]["loaded"] = 2
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))
	eq(saved["version"], Ship.VERSION, "the current ship save version")
	eq(saved["components"]["version"], Components.VERSION, "the current components version")
	var back := Ship.new_starter()
	eq(back.load_dict(saved), "", "loads")
	eq(Ammo.item_in(back, d["rack"]), "missile", "the rack's item")
	eq(Ammo.count_in(back, d["rack"]), 13, "and count")
	eq(Ammo.loaded(back, d["gun"]), 2, "the gun's loaded units")


func test_an_old_save_loads_with_empty_racks_and_no_belts() -> void:
	var d := Fx.with_rack()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(d["ship"].to_dict()))
	saved["version"] = 4
	saved["components"]["version"] = 3
	saved.erase("belts")
	for rec in saved["components"]["instances"]:
		rec.erase("ammo")
		rec.erase("n")
		rec.erase("loaded")
	var back := Ship.new_starter()
	eq(back.load_dict(saved), "", "a version 4 ship with version 3 parts loads")
	eq(Ammo.count_in(back, d["rack"]), 0, "the rack is empty")
	eq(Ammo.loaded(back, d["gun"]), 0, "nothing loaded")
	check(back.belts.cells.is_empty() and not back.belts.known, "no belts")


func test_every_design_without_a_rack_still_fires_from_the_cargo() -> void:
	for path in ["res://data/ships/starter_rustbucket.json", "res://data/ships/starter_courier.json", "res://data/ships/starter_prism.json", "res://data/ships/pirate_raider.json"]:
		var ship := Ship.from_design(path)
		check(ship != null, path + " loads")
		if ship == null or Ammo.uses_racks(ship):
			continue
		for uid in ship.components.instances:
			var item := Ammo.ammo_item(ship.components.instances[uid]["id"])
			if item != "":
				ship.inventory.add(item, 5)
				eq(Ammo.refusal(ship, uid, item, 1), "", "%s: %s draws from the cargo" % [path, ship.components.instances[uid]["id"]])


func test_removing_a_rack_returns_its_units_to_the_cargo() -> void:
	var d := Fx.with_rack()
	var ship: Ship = d["ship"]
	Fx.stock(ship, d["rack"], "missile", 11)
	ship.components.instances[d["gun"]]["loaded"] = 1
	var held: Dictionary = Ammo.unload(ship, d["rack"])
	eq(held["n"], 11, "11 came out")
	eq(ship.inventory.count("missile"), 11, "into the cargo")
	var held_gun: Dictionary = Ammo.unload(ship, d["gun"])
	eq(held_gun["loaded"], 1, "the gun's loaded unit too")
	eq(ship.inventory.count("missile"), 12, "12 in all")
