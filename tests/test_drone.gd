extends "res://tests/base_test.gd"
## The repair drone (playtest 2, R1; species `drone` in data/species.json, crew.json `drone` and `drone_jobs`): a small robot nobody
## steers that mends, fights fires and reloads, draws 1 power with no cable, breaks instead of dying, comes with every run and from
## the fabricator, and is not crew (scripts/crew/jobs.gd, power.gd, mortality.gd, run_start.gd, crew_member.gd).

const Fixture = preload("res://tests/fixture_ship.gd")
const Fx = preload("res://tests/fixture_ammo.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const CrewBar = preload("res://scripts/ui/crew_bar.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const Endings = preload("res://scripts/space/endings.gd")
const GameOver = preload("res://scripts/ui/game_over.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Mortality = preload("res://scripts/crew/mortality.gd")
const PartEffects = preload("res://scripts/sim/part_effects.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const Power = preload("res://scripts/sim/power.gd")
const RunStart = preload("res://scripts/space/run_start.gd")
const Salvage = preload("res://scripts/space/salvage.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const CrewAbilities = preload("res://scripts/crew/crew_abilities.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")

const STARTERS := ["res://data/ships/starter_rustbucket.json", "res://data/ships/starter_courier.json", "res://data/ships/starter_prism.json"]
const STEP := 0.1


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, want, got])


## A drone with its 1x1 body on cell (x, y).
func _drone(ship: Ship, x: int, y: int, p_name := "Drone") -> CrewMember:
	var m := CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y), 1), "drone")
	ship.crew.append(m)
	return m


## A human whose 2x2 body has its top-left cell on (x, y).
func _human(ship: Ship, p_name: String, x: int, y: int, player := false) -> CrewMember:
	var m := CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)))
	m.is_player = player
	ship.crew.append(m)
	return m


## The room ship with a reactor on a cable: 8 power and nothing using it.
func _powered() -> Ship:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "reactor_mk1", 10, 10)
	Fixture.wire(ship, [Vector2i(10, 10)])
	ship.refresh()
	return ship


## Run the crew of `ship` for `seconds`, refreshing the ship each step as the sim does. Returns the job types seen on anyone in `who`.
func _run(jobs: Jobs, ship: Ship, seconds: float, who: Array = []) -> Dictionary:
	var seen := {}
	for i in roundi(seconds / STEP):
		ship.refresh()
		jobs.tick(ship, STEP)
		for m in who:
			if not m.job.is_empty():
				seen[str(m.job["type"])] = true
	return seen


# --- what it is ---------------------------------------------------------------------------------------------

func test_a_drone_is_a_small_mechanical_body_with_60_hp_that_needs_no_air() -> void:
	var m := CrewMember.new("Drone", Vector2.ZERO, "drone")
	check(m.is_drone(), "the species drone is a drone")
	check(not CrewMember.new("Soldier", Vector2.ZERO).is_drone(), "a person is not")
	check(CrewMember.is_drone_species("drone") and not CrewMember.is_drone_species("human"), "by species")
	near(m.max_hp, 60.0, "60 hp")
	eq(m.body_size, 1, "one cell across")
	var t := TraitSet.of(m)
	check(bool(t["mechanical"]), "mechanical")
	near(float(t["o2_use"]), 0.0, "uses no air")
	check(bool(t["vacuum_walk"]), "and does not suffocate")
	near(float(t["damage_taken"]["fire"]), 0.25, "fire hurts it a quarter")
	for kind in ["repair", "breach", "extinguish", "restock"]:
		near(float(t["work_mult"][kind]), 0.6, kind + " at 0.6")
	near(float(t["heal_mult"]["bed"]) + float(t["heal_mult"]["medbay"]), 0.0, "no bed or medbay heals it")
	check(CrewAbilities.of(m).is_empty(), "and it has no ability")


# --- its jobs -----------------------------------------------------------------------------------------------

func test_a_drone_puts_out_a_fire_and_seals_a_breach_on_its_own() -> void:
	var ship := _powered()
	var d := _drone(ship, 14, 12)
	ship.fires[Vector2i(12, 13)] = 0.3
	ship.grid.breach(Vector2i(15, 8))
	ship.mark_dirty()
	ship.refresh()
	var jobs := Jobs.new()
	jobs.build_board(ship)
	check(jobs.board.has("fire:12,13") and jobs.board.has("breach:15,8"), "a fire and a breach on the board")
	var seen := _run(jobs, ship, 90.0, [d])
	check(seen.has("extinguish"), "it took the fire")
	check(seen.has("repair_breach"), "and the breach")
	check(ship.fires.is_empty(), "the fire is out")
	check(not ship.grid.breached.has(Vector2i(15, 8)), "the breach is sealed")


func test_a_drone_is_slower_than_a_person_by_its_work_mult() -> void:
	var fast := _powered()
	var slow := _powered()
	var h := _human(fast, "Soldier", 14, 12)
	var d := _drone(slow, 14, 12)
	for s in [fast, slow]:
		s.grid.breach(Vector2i(15, 8))
		s.mark_dirty()
		s.refresh()
	var jobs_h := Jobs.new()
	var jobs_d := Jobs.new()
	var t_h := _time_to_seal(jobs_h, fast)
	var t_d := _time_to_seal(jobs_d, slow)
	check(t_h > 0.0 and t_d > 0.0, "both seal it (%s, %s s)" % [t_h, t_d])
	check(t_d > t_h * 1.4, "the drone takes about 1/0.6 as long: %s s against %s s" % [t_d, t_h])
	check(h.is_drone() == false and d.is_drone(), "(who is who)")


func _time_to_seal(jobs: Jobs, ship: Ship) -> float:
	for i in 1200:
		ship.refresh()
		jobs.tick(ship, STEP)
		if not ship.grid.breached.has(Vector2i(15, 8)):
			return (i + 1) * STEP
	return -1.0


func test_a_drone_restocks_an_ammo_rack_from_the_cargo() -> void:
	var f := Fx.with_rack()
	var ship: Ship = f["ship"]
	ship.inventory.add("missile", 40)
	var d := _drone(ship, 20, 18)
	ship.refresh()
	check(Power.drone_fed(ship.power_state, "Drone"), "the reactor has the power to spare")
	var jobs := Jobs.new()
	var seen := _run(jobs, ship, 60.0, [d])
	check(seen.has("restock"), "it took the restock job")
	check(not seen.has("man_station"), "and not the gun's post")
	eq(Ammo.count_in(ship, f["rack"]), 20, "the rack is full")
	eq(ship.inventory.count("missile"), 20, "from the cargo")


func test_a_drone_never_takes_a_station_a_revive_or_the_mending_of_a_crewmate() -> void:
	var ship := _powered()
	Fixture.put(ship, "helm", 19, 10)
	var d := _drone(ship, 14, 12)
	var hurt := _drone(ship, 16, 14, "Drone 2")
	hurt.hp = 20.0
	var down := _human(ship, "Rook", 12, 14)
	down.hp = 0.0
	ship.refresh()
	var jobs := Jobs.new()
	jobs.build_board(ship)
	var types := {}
	for j in jobs.board.values():
		types[str(j["type"])] = true
	check(types.has("man_station") and types.has("revive") and types.has("repair_crew"), "the board offers a station, a revive and a mending")
	var seen := _run(jobs, ship, 40.0, [d, hurt])
	var allowed: Array = CrewMember.config()["drone_jobs"]
	for t in seen:
		check(allowed.has(t), "a drone held only a job of drone_jobs, not '%s'" % t)
	check(ship.manned.is_empty(), "nobody mans the helm")
	near(down.hp, 0.0, "Rook is not revived")
	near(hurt.hp, 20.0, "and the drone does not mend the other drone")


# --- power --------------------------------------------------------------------------------------------------

func test_a_drone_with_no_power_stands_still_and_says_so_and_works_again_with_power() -> void:
	var ship := Fixture.room_ship()  # no reactor
	var d := _drone(ship, 14, 12)
	ship.fires[Vector2i(12, 13)] = 0.3
	ship.refresh()
	check(not Power.drone_fed(ship.power_state, d.name), "no power for it")
	eq(Jobs.drone_status(ship, d), "no power", "it says so")
	var at := d.pos
	var jobs := Jobs.new()
	var seen := _run(jobs, ship, 20.0, [d])
	check(seen.is_empty(), "it took no job")
	check(ship.fires.has(Vector2i(12, 13)), "the fire burns on")
	eq(d.pos, at, "and it did not move")
	Fixture.put(ship, "reactor_mk1", 10, 10)
	Fixture.wire(ship, [Vector2i(10, 10)])
	ship.refresh()
	eq(Jobs.drone_status(ship, d), "", "power is back")
	_run(jobs, ship, 30.0, [d])
	check(ship.fires.is_empty(), "and it put the fire out")


func test_a_drone_draws_one_power_with_no_cable_and_the_surplus_decides_who_runs() -> void:
	var ship := _powered()
	var cables_before: int = ship.cables.cells.size()
	var a := _drone(ship, 14, 12)
	ship.refresh()
	var st: Dictionary = ship.power_state
	near(float(st["networks"][0]["supply"]), 8.0, "the reactor makes 8")
	near(float(st["drones"]["demand"]), 1.0, "the drone asks for 1")
	near(float(st["drones"]["used"]), 1.0, "and gets it")
	eq(ship.cables.cells.size(), cables_before, "with no cable laid for it")
	check(not ship.cables.cells.has(a.cell()), "(it is on none)")
	# two shields use 6 of the 8: two drones fit in the 2 left, a third does not
	var s1 := Fixture.put(ship, "shield_mk1", 14, 10)
	var s2 := Fixture.put(ship, "shield_mk1", 17, 10)
	check(s1 > 0 and s2 > 0, "two shields placed")
	Fixture.wire(ship, [Vector2i(11, 10), Vector2i(12, 10), Vector2i(13, 10), Vector2i(14, 10), Vector2i(15, 10), Vector2i(16, 10), Vector2i(17, 10)])
	_drone(ship, 14, 14, "Drone 2")
	_drone(ship, 16, 14, "Drone 3")
	ship.refresh()
	st = ship.power_state
	near(float(st["networks"][0]["supply"]) - float(st["networks"][0]["used"]), 2.0, "2 power left over by the parts")
	check(Power.drone_fed(st, "Drone") and Power.drone_fed(st, "Drone 2") and not Power.drone_fed(st, "Drone 3"), "the first two run, in name order")
	near(float(st["drones"]["demand"]), 3.0, "all three are asked for (the top bar shows it)")
	near(float(st["drones"]["used"]), 2.0, "two are paid")
	check(st["powered"][s1] and st["powered"][s2], "the shields come first and are on")


func test_the_pure_feed_takes_the_surplus_of_every_network_and_ignores_the_broken() -> void:
	var state := {"networks": [{"supply": 5, "used": 4, "demand": 4}, {"supply": 3, "used": 2.5, "demand": 2.5}]}
	Power.feed_drones(state, ["A", "B", "C"], 1.0)
	check(Power.drone_fed(state, "A") and not Power.drone_fed(state, "B") and not Power.drone_fed(state, "C"), "1 + 0.5 spare: one drone")
	check(not Power.drone_fed(state, "nobody"), "an unknown name is off")
	var none := {"networks": []}
	Power.feed_drones(none, ["A"], 1.0)
	check(not Power.drone_fed(none, "A"), "no networks, no power")
	var ship := _powered()
	var d := _drone(ship, 14, 12)
	ship.refresh()
	near(float(ship.power_state["drones"]["used"]), 1.0, "a working drone is paid")
	d.hurt(1000.0)
	ship.refresh()
	near(float(ship.power_state["drones"]["used"]), 0.0, "a broken one is not")
	near(float(ship.power_state["drones"]["demand"]), 0.0, "nor asked for")


# --- broken, not dead ------------------------------------------------------------------------------------------

func test_at_zero_hp_a_drone_is_broken_not_dead_and_a_crewmates_repair_brings_it_back() -> void:
	var ship := _powered()
	var d := _drone(ship, 14, 12)
	var rook := _human(ship, "Rook", 14, 10)
	var control := _human(ship, "Grub", 18, 14)
	d.hurt(1000.0)
	control.hurt(1000.0)
	ship.refresh()
	check(d.is_down(), "0 hp")
	eq(Jobs.drone_status(ship, d), "broken", "it says broken")
	var lines := Mortality.tick(ship, 500.0)
	check(ship.crew.has(d) and ship.dead_crew.find("Drone") < 0, "500 s later it is still aboard and not on the list of the dead")
	near(d.down_t, 0.0, "it never bled")
	near(Mortality.bleed_frac(d), 0.0, "no red ring")
	check(not ship.crew.has(control) and ship.dead_crew.has("Grub"), "(a person in the same state has bled out)")
	check(lines.size() == 1, "one line, for the person")
	var jobs := Jobs.new()
	jobs.build_board(ship)
	check(jobs.board.has("mend:Drone") and not jobs.board.has("revive:Drone"), "a mending job, not a revive")
	_run(jobs, ship, 30.0, [rook])
	check(not d.is_down(), "Rook mended it: above 0 hp")
	near(d.hp, d.max_hp, "all the way", 0.01)
	var seen := _run(jobs, ship, 3.0, [d])
	check(Jobs.drone_status(ship, d) == "", "it is working again")
	ship.fires[Vector2i(12, 13)] = 0.3
	_run(jobs, ship, 20.0, [d])
	check(ship.fires.is_empty() and seen.size() >= 0, "and it puts out a fire")


func test_the_soldier_mends_a_broken_drone_by_hand() -> void:
	var ship := _powered()
	var d := _drone(ship, 14, 12)
	var me := _human(ship, "Soldier", 14, 13, true)  # beside it
	d.hurt(1000.0)
	var jobs := Jobs.new()
	jobs.build_board(ship)
	eq(jobs.hand_work(ship, me, 1.0), "mend:Drone", "holding E beside it works the mending")
	check(not d.is_down(), "a second of it and the drone is above 0 hp")


func test_a_drone_takes_no_orders_and_cannot_be_picked() -> void:
	var ship := _powered()
	var d := _drone(ship, 14, 12)
	var me := _human(ship, "Soldier", 10, 14, true)
	var jobs := Jobs.new()
	check(not Jobs.order_move(ship, d, Vector2i(16, 14)), "a middle-click order is refused")
	var helm := Fixture.put(ship, "helm", 19, 10)
	ship.components.instances[helm]["status"] = "malfunction"
	eq(jobs.order_repair(ship, helm), "no crew to send", "nor does the F order send it (only the soldier and the drone are aboard)")
	var v := _view(ship)
	var view: CrewView = v["view"]
	eq(view.pick_at(d.pos), null, "a click on the drone selects nobody")
	view.select(d)
	check(view.order_target() != d, "and a drone selected is not the one a middle click sends")
	eq(view.order_target(), null, "with only the soldier and a drone aboard there is nobody to send")
	var bar: CrewBar = v["bar"]
	var rects := CrewBar.card_rects(ship.crew.size(), bar.size)
	view.select(null)
	eq(bar.click(rects[ship.crew.find(d)].get_center()), "drone", "its card takes the click")
	eq(view.selected, null, "and selects nothing")
	check(me.is_player, "(the soldier is the soldier)")
	_free(v)


# --- the start, the recipe, the pools --------------------------------------------------------------------------

func test_every_run_starts_with_the_soldier_plus_one_drone_and_the_starters_files_have_none() -> void:
	for path in STARTERS:
		var ship := Ship.from_design(path)
		eq(ship.crew_plan, [{"name": "Soldier", "species": "human"}], path + ": the design itself lists the soldier alone")
		var lines := RunStart.apply_ship(ship, {}, null)
		check(lines.any(func(l): return str(l).contains("repair drone")), path + ": the run says the drone is aboard")
		Jobs.spawn_crew(ship)
		eq(ship.crew.map(func(m): return m.name), ["Soldier", "Drone"], path + ": the soldier and one drone")
		check(ship.crew[0].is_player and not ship.crew[1].is_player, path + ": the soldier is the player's")
		check(ship.crew[1].is_drone() and ship.crew[1].body_size == 1, path + ": the second is the drone")
		check(Pathfinder.body_ok(ship.grid, ship.crew[1].anchor(), Callable(), 1), path + ": standing where a body fits")
		check(not RunStart.add_drone(ship), path + ": a second call adds none")
		eq(ship.crew_plan.size(), 2, path + ": still two entries")


func test_a_design_with_no_crew_list_still_starts_as_the_soldier_and_the_drone() -> void:
	var ship := Ship.from_design(STARTERS[0])
	ship.crew_plan = []
	check(RunStart.add_drone(ship), "added")
	Jobs.spawn_crew(ship)
	eq(ship.crew.map(func(m): return m.name), ["Soldier", "Drone"], "the soldier first, so the drone is not alone aboard")


func test_the_drone_recipe_is_a_blueprint_to_find_and_adds_a_drone_at_the_fabricator() -> void:
	var fresh := Ship.from_design(STARTERS[0])
	check(fresh.crafting.has("repair_drone"), "the recipe exists")
	check(not fresh.crafting.is_known("repair_drone"), "its blueprint is not known at the start")
	eq(fresh.crafting.def("repair_drone")["materials"], {"scrap": 60, "copper": 20, "polymer": 10}, "scrap 60, copper 20, polymer 10")
	var ship := Fixture.room_ship()
	Fixture.put(ship, "reactor_mk1", 10, 10)
	var fab := Fixture.put(ship, "fabricator", 14, 10)
	Fixture.wire(ship, [Vector2i(10, 10), Vector2i(11, 10), Vector2i(12, 10), Vector2i(13, 10), Vector2i(14, 10)])
	ship.inventory.add("polymer", 20)
	ship.refresh()
	check(fab > 0, "a fabricator")
	check(ship.crafting.can_craft("repair_drone", ship.inventory, Workshop.best(ship)) != "", "without the blueprint it is refused")
	ship.crafting.unlock("repair_drone")
	eq(ship.crafting.enqueue("repair_drone", ship.inventory, Workshop.best(ship)), "", "queued")
	eq(ship.inventory.count("polymer"), 10, "the materials are paid")
	var sim := ShipSim.new()
	sim.ships = [ship]
	for i in 80:
		sim.step(0.5)
	eq(ship.crew.size(), 1, "one body aboard")
	var d: CrewMember = ship.crew[0]
	check(d.is_drone() and d.name == "Drone", "a drone")
	check(d.pos.distance_to(Pathfinder.centre_of(ship.components.instances[fab]["cells"][0], 1)) < 6.0, "beside the fabricator")
	eq(ship.inventory.count("repair_drone"), 0, "it is not left in the cargo")
	ship.inventory.add("repair_drone", 1)  # (a second one, as a station sells it)
	Jobs.launch_drones(ship)
	eq(ship.crew.map(func(m): return m.name), ["Drone", "Drone 2"], "the next one is Drone 2")


func test_a_station_sells_the_drone_and_it_goes_aboard() -> void:
	var c := Campaign.new(3)
	var ship := Fixture.room_ship()
	ship.inventory.add("credits", 2000)
	var station := ""
	for id in c.cfg["stations"]:
		if c.stock_price(str(id), "repair_drone") > 0:
			station = str(id)
	check(station != "", "some station stocks it")
	var r := c.buy(ship, station, "repair_drone")
	check(r["ok"], "bought: " + str(r["text"]))
	eq(ship.crew.size(), 1, "aboard at once")
	check(ship.crew[0].is_drone(), "a drone")
	eq(ship.inventory.count("repair_drone"), 0, "not in the cargo")


func test_a_wreck_may_offer_to_scan_the_drone_blueprint_without_touching_the_campaign_rng() -> void:
	var ship := Ship.from_design(STARTERS[0])
	var hits := 0
	for seed_value in range(1, 41):
		var c := Campaign.new(seed_value)
		var before := c.rng.state
		var rid := Salvage.drone_scan(ship, c)
		eq(c.rng.state, before, "seed %d: the rng stream is untouched" % seed_value)
		eq(Salvage.drone_scan(ship, c), rid, "seed %d: the same wreck, the same offer" % seed_value)
		hits += 1 if rid == "repair_drone" else 0
	check(hits > 0 and hits < 25, "about a fifth of the wrecks (%d of 40)" % hits)
	ship.crafting.unlock("repair_drone")
	eq(Salvage.drone_scan(ship, Campaign.new(1)), "", "nothing once the blueprint is known")


func test_the_scan_row_sits_before_the_strip_row_and_teaches_the_blueprint() -> void:
	var ship := Ship.from_design(STARTERS[0])
	var raider := Ship.from_design("res://data/ships/pirate_raider.json")
	var found := false
	for seed_value in range(1, 41):
		var c := Campaign.new(seed_value)
		if Salvage.drone_scan(ship, c) == "":
			continue
		found = true
		var rows: Array = Salvage.event_for(raider, "won", c, ship)["choices"]
		var at := -1
		for i in rows.size():
			if str(rows[i]["text"]).begins_with("Scan the service drone bay"):
				at = i
		check(at > 0, "seed %d: a drone scan row" % seed_value)
		eq(rows[at]["outcomes"][0]["effects"], {"blueprint": ["repair_drone"]}, "it teaches the drone blueprint")
		check(str(rows[rows.size() - 1]["text"]).begins_with("Strip her"), "and the strip row is still last")
		break
	check(found, "some wreck offers it")


# --- not crew ------------------------------------------------------------------------------------------------------

func test_drones_do_not_count_as_crew() -> void:
	var ship := _powered()
	var me := _human(ship, "Soldier", 12, 14, true)
	var d := _drone(ship, 14, 12)
	var c := Campaign.new(1)
	eq(c.lose_crew(ship), "", "an event that makes crew leave finds nobody but the soldier and a drone")
	check(ship.crew.has(d), "and the drone stays")
	var rook := _human(ship, "Rook", 16, 14)
	eq(c.lose_crew(ship), "Rook", "Rook goes, not the drone")
	check(not ship.crew.has(rook) and ship.crew.has(d), "(the drone is still aboard)")
	eq(Endings.crew_alive(ship), ["Soldier"], "the crew alive on the end screen")
	eq(GameOver.stats_of(c, ship)["crew"], 1, "and in the run's numbers")
	eq(Endings.design_of(ship)["crew"], [{"name": "Soldier", "species": "human"}], "a hall-of-ships design does not carry the drone")
	var gun := Fixture.put(ship, "laser_mk1", 14, 14)
	var near_me := PartEffects.crew_count(ship, gun, "")
	d.pos = Pathfinder.centre_of(ship.components.instances[gun]["cells"][0], 1)
	eq(PartEffects.crew_count(ship, gun, ""), near_me, "a drone in a room is no crew there")
	check(me.is_player, "(the soldier)")


# --- saves ---------------------------------------------------------------------------------------------------------

func test_a_save_keeps_a_drone_broken_state_included() -> void:
	var ship := _powered()
	_human(ship, "Soldier", 12, 14, true)
	var d := _drone(ship, 14, 12)
	var e := _drone(ship, 16, 14, "Drone 2")
	d.hurt(1000.0)
	e.hurt(15.0)
	ship.crew_plan = [{"name": "Soldier", "species": "human", "player": true}, {"name": "Drone", "species": "drone"}]
	var data: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))  # through the file, as Ctrl+S / Continue do
	var back := Ship.new_starter()
	eq(back.load_dict(data), "", "loads")
	eq(back.crew.map(func(m): return m.name), ["Soldier", "Drone", "Drone 2"], "the same three")
	var bd: CrewMember = back.crew[1]
	var be: CrewMember = back.crew[2]
	check(bd.is_drone() and be.is_drone() and not back.crew[0].is_drone(), "the drones are still drones")
	near(bd.hp, 0.0, "the broken one is still broken")
	check(bd.is_down() and back.dead_crew.is_empty(), "and not dead")
	near(be.hp, 45.0, "the hurt one is still hurt")
	near(be.max_hp, 60.0, "of 60")
	eq(bd.body_size, 1, "small")
	eq(bd.pos, d.pos, "where they were")
	back.refresh()
	near(float(back.power_state["drones"]["used"]), 1.0, "and only the working one draws power")
	eq(Jobs.drone_status(back, bd), "broken", "and says broken")
	var jobs := Jobs.new()
	Jobs.spawn_crew(back)
	eq(back.crew.size(), 3, "spawning the crew again adds no second drone")
	jobs.build_board(back)
	check(jobs.board.has("mend:Drone") and jobs.board.has("mend:Drone 2"), "both are for a crewmate to mend")


# --- looks ---------------------------------------------------------------------------------------------------------

func test_the_card_and_the_art_are_made_for_a_drone() -> void:
	var ship := _powered()
	var me := _human(ship, "Soldier", 12, 14, true)
	var d := _drone(ship, 14, 12)
	ship.refresh()
	var v := _view(ship)
	var bar: CrewBar = v["bar"]
	eq(bar._doing(ship, d), "idle", "an idle drone is idle")
	var off := Fixture.room_ship()
	var lost := _drone(off, 14, 12)
	off.refresh()
	eq(bar._doing(off, lost), "no power", "the card says no power")
	lost.hurt(1000.0)
	eq(bar._doing(off, lost), "broken", "or broken")
	check(PersonDrawer.drone_extras(me, ship).is_empty(), "a person has no drone pose")
	var pose := PersonDrawer.drone_extras(d, ship)
	check(pose["drone"] and not pose["off"] and not pose["work"], "a drone's pose: on and idle")
	eq(PersonDrawer.drone_extras(lost, off)["off"], false, "(a broken one is not 'off', it is down)")
	_free(v)


# --- helpers ---------------------------------------------------------------------------------------------------------

## A crew view on `ship` in play mode with a crew bar bound to it (see test_crew_abilities.gd).
func _view(ship: Ship) -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [ship]
	var build := BuildMode.new()
	build.build_on = false
	var view := CrewView.new()
	view.sim = sim
	view.build = build
	var bar := CrewBar.new()
	bar.view = view
	bar.size = Vector2(1600.0, 900.0)
	view._bar = bar
	return {"view": view, "bar": bar, "sim": sim, "build": build}


func _free(d: Dictionary) -> void:
	for k in d:
		d[k].free()
