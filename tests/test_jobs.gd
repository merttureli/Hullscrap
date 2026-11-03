extends "res://tests/base_test.gd"
## Crew jobs (scripts/crew/jobs.gd): the board, who takes what, fighting fires, repairs, manning,
## health, the starting crew, and the crew working on during a fight.

const Fixture = preload("res://tests/fixture_ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")

const STARTERS := ["res://data/ships/starter_rustbucket.json", "res://data/ships/starter_courier.json", "res://data/ships/starter_prism.json"]
## A crew of four for the tests that need a crew list to spawn: the real starters start with the soldier alone (playtest 2, A1).
const TEAM := [{"name": "Soldier", "species": "human"}, {"name": "Ada", "species": "human"}, {"name": "Rook", "species": "basalt"}, {"name": "Juno", "species": "fenn"}]
const PIRATE := "res://data/ships/pirate_raider.json"
const STEP := 0.1


## A person whose 2x2 body has its top-left cell on (x, y).
func _npc(p_name: String, x: int, y: int) -> CrewMember:
	return CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)))


func _player(x: int, y: int) -> CrewMember:
	var m := _npc("Soldier", x, y)
	m.is_player = true
	return m


## Run the crew of `ship` for `seconds` in steps of 0.1 s (no fire growth: Jobs only).
func _run(jobs: Jobs, ship: Ship, seconds: float) -> void:
	for i in roundi(seconds / STEP):
		jobs.tick(ship, STEP)


func _distinct(list: Array) -> int:
	var seen := {}
	for x in list:
		seen[x] = true
	return seen.size()


func _log_index(ship: Ship, text: String) -> int:
	for i in ship.events.size():
		if ship.events[i]["text"] == text:
			return i
	return -1


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, want, got])


## Seconds (in 0.1 steps) until `done` is true, 0.0 - 60.0; -1 if it never was.
func _time_until(jobs: Jobs, ship: Ship, done: Callable) -> float:
	for i in 600:
		jobs.tick(ship, STEP)
		if done.call():
			return (i + 1) * STEP
	return -1.0


## The work time of job `type` in seconds (data/crew.json jobs: repair_breach 14, repair_component 12, repair_belt 4).
func _secs(type: String) -> float:
	return float(Jobs.jcfg()[type]["seconds"])


# --- the board and its order ---------------------------------------------------------------------

## A room with a helm, an engine that malfunctions, a fire, and a breach. Returns the uids too.
func _trouble() -> Dictionary:
	var ship := Fixture.room_ship()
	var d := {"ship": ship}
	d["helm"] = Fixture.put(ship, "helm", 19, 10)
	d["engine"] = Fixture.put(ship, "engine_mk1", 15, 14)
	ship.components.instances[d["engine"]]["status"] = "malfunction"
	ship.fires[Vector2i(12, 12)] = 0.3
	ship.grid.breach(Vector2i(15, 8))
	ship.mark_dirty()
	ship.refresh()
	return d


func test_the_board_lists_fire_before_breach_before_part_before_station() -> void:
	var d := _trouble()
	var jobs := Jobs.new()
	jobs.build_board(d["ship"])
	var keys: Array = Jobs.by_priority(jobs.board.values()).map(func(j): return j["key"])
	eq(keys, ["fire:12,12", "breach:15,8", "fix:%d" % d["engine"], "post:%d" % d["helm"]], "highest priority first")
	eq([jobs.board["fire:12,12"]["priority"], jobs.board["breach:15,8"]["priority"], jobs.board["fix:%d" % d["engine"]]["priority"], jobs.board["post:%d" % d["helm"]]["priority"]], [100, 90, 80, 50], "100 / 90 / 80 / 50")


func test_weapons_engines_and_shields_come_first_in_a_fight() -> void:
	var ship := Fixture.room_ship()
	var laser := Fixture.put(ship, "laser_mk1", 15, 10)
	var engine := Fixture.put(ship, "engine_mk1", 15, 14)
	var radiator := Fixture.put(ship, "radiator", 10, 10)
	for uid in [laser, engine, radiator]:
		ship.components.instances[uid]["status"] = "malfunction"
	var jobs := Jobs.new()
	jobs.build_board(ship)
	eq([jobs.board["fix:%d" % laser]["priority"], jobs.board["fix:%d" % radiator]["priority"]], [80, 80], "calm: all alike")
	jobs.combat = true
	jobs.build_board(ship)
	eq([jobs.board["fix:%d" % laser]["priority"], jobs.board["fix:%d" % engine]["priority"], jobs.board["fix:%d" % radiator]["priority"]], [90, 90, 80], "in a fight: weapon and engine +10")


func test_an_overheated_part_is_not_a_job_but_a_disabled_one_is() -> void:
	var ship := Fixture.room_ship()
	var uid := Fixture.put(ship, "engine_mk1", 15, 14)
	var jobs := Jobs.new()
	ship.components.instances[uid]["status"] = "overheated"
	jobs.build_board(ship)
	check(not jobs.board.has("fix:%d" % uid), "it just needs time")
	ship.components.instances[uid]["status"] = "disabled"
	jobs.build_board(ship)
	check(jobs.board.has("fix:%d" % uid), "disabled: repair")


func test_only_the_helm_is_manned_unless_the_data_says_so() -> void:
	var ship := Fixture.room_ship()
	var helm := Fixture.put(ship, "helm", 19, 10)
	var laser := Fixture.put(ship, "laser_mk1", 15, 10)
	var jobs := Jobs.new()
	ship.components.by_id["laser_mk1"]["manned"] = false
	jobs.build_board(ship)
	eq(jobs.board.keys(), ["post:%d" % helm], "the helm always, an unmanned laser not")
	ship.components.by_id["laser_mk1"]["manned"] = true  # weapons are manned stations in the data (lead decision)
	jobs.build_board(ship)
	check(jobs.board.has("post:%d" % laser), "a weapon with manned: true gets a post")
	eq(jobs.board["post:%d" % laser]["priority"], 45, "at 45 out of a fight: the helm (50) is manned first, the autopilot needs it")
	eq(jobs.board["post:%d" % helm]["priority"], 50, "the helm at 50")
	jobs.combat = true
	jobs.build_board(ship)
	eq(jobs.board["post:%d" % laser]["priority"], 50, "in a fight at 50 like the helm")


# --- who takes what ------------------------------------------------------------------------------

func test_one_crew_member_works_through_fire_breach_part_station_in_that_order() -> void:
	var d := _trouble()
	var ship: Ship = d["ship"]
	var m := _npc("Ada", 13, 14)
	ship.crew.append(m)
	var jobs := Jobs.new()
	_run(jobs, ship, 60.0)
	var fire_out := _log_index(ship, "Fire out")
	var sealed := _log_index(ship, "Breach sealed")
	var fixed := _log_index(ship, "Concord Thruster Mk1 repaired")
	check(fire_out >= 0 and sealed >= 0 and fixed >= 0, "all three were done: %s" % str(ship.events.map(func(e): return e["text"])))
	check(fire_out < sealed and sealed < fixed, "fire, then breach, then part")
	check(ship.fires.is_empty() and ship.grid.breached.is_empty(), "nothing burns, nothing is open")
	eq(ship.components.instances[d["engine"]]["status"], "ok", "the engine runs")
	check(ship.manned.has(d["helm"]), "and then the helm is manned")
	eq(ship.manned[d["helm"]], "Ada", "by her")


func test_a_free_crew_member_picks_the_nearest_of_equal_jobs() -> void:
	var ship := Fixture.room_ship()
	ship.fires[Vector2i(10, 15)] = 0.5
	ship.fires[Vector2i(20, 10)] = 0.5
	var near_one := _npc("Near", 18, 11)
	ship.crew.append(near_one)
	var jobs := Jobs.new()
	jobs.tick(ship, STEP)
	eq(near_one.job["key"], "fire:20,10", "the fire close by, not the one across the room")


func test_two_crew_do_not_both_take_a_one_place_job() -> void:
	var ship := Fixture.room_ship()
	var uid := Fixture.put(ship, "engine_mk1", 15, 14)
	ship.components.instances[uid]["status"] = "malfunction"
	var a := _npc("A", 13, 14)
	var b := _npc("B", 13, 11)
	ship.crew.append_array([a, b])
	var jobs := Jobs.new()
	jobs.tick(ship, STEP)
	var taken := [a, b].filter(func(m): return not m.job.is_empty())
	eq(taken.size(), 1, "one repair, one repairer")
	check(a.job.has("key") and b.job.is_empty(), "the other has nothing to do")


func test_jobs_nobody_works_on_go_first() -> void:
	var ship := Fixture.room_ship()
	ship.fires[Vector2i(12, 12)] = 0.5
	ship.fires[Vector2i(20, 15)] = 0.5
	var a := _npc("A", 13, 12)
	var b := _npc("B", 16, 12)  # nearer to the first fire than to the second
	ship.crew.append_array([a, b])
	var jobs := Jobs.new()
	jobs.tick(ship, STEP)
	eq(a.job["key"], "fire:12,12", "the first takes the near fire")
	eq(b.job["key"], "fire:20,15", "the second takes the one nobody works on, though the first has a free place")


func test_a_crew_member_switches_to_a_job_30_points_higher() -> void:
	var ship := Fixture.room_ship()
	var helm := Fixture.put(ship, "helm", 19, 10)
	var engine := Fixture.put(ship, "engine_mk1", 15, 14)
	var m := _npc("Ada", 17, 10)  # next to the helm
	ship.crew.append(m)
	var jobs := Jobs.new()
	_run(jobs, ship, 0.5)
	eq(m.job["key"], "post:%d" % helm, "at the helm")
	check(ship.manned.has(helm), "manning it")
	ship.components.instances[engine]["status"] = "malfunction"  # 80 against 50: exactly 30 more
	_run(jobs, ship, 1.2)
	eq(m.job.get("type"), "repair_component", "she goes to fix the engine")
	check(not ship.manned.has(helm), "and leaves the helm")


func test_a_crew_member_keeps_a_job_when_the_new_one_is_less_than_30_higher() -> void:
	var ship := Fixture.room_ship()
	var engine := Fixture.put(ship, "engine_mk1", 15, 14)
	ship.components.instances[engine]["status"] = "malfunction"
	var m := _npc("Ada", 13, 14)
	ship.crew.append(m)
	var jobs := Jobs.new()
	_run(jobs, ship, 1.0)
	eq(m.job["key"], "fix:%d" % engine, "repairing")
	ship.grid.breach(Vector2i(15, 8))  # 90: 10 higher
	ship.mark_dirty()
	_run(jobs, ship, 1.5)
	eq(m.job.get("key"), "fix:%d" % engine, "she keeps at the repair")
	ship.fires[Vector2i(12, 12)] = 0.9  # 100: 20 higher
	_run(jobs, ship, 1.5)
	eq(m.job.get("key"), "fix:%d" % engine, "and at the repair")
	check(float(jobs.progress.get("fix:%d" % engine, 0.0)) > 0.0, "(it is making progress)")


func test_a_fire_pulls_a_crew_member_off_a_station() -> void:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "helm", 19, 10)
	var m := _npc("Ada", 17, 10)
	ship.crew.append(m)
	var jobs := Jobs.new()
	_run(jobs, ship, 0.5)
	eq(m.job["type"], "man_station", "at the helm")
	ship.fires[Vector2i(12, 12)] = 0.9
	_run(jobs, ship, 1.2)
	eq(m.job.get("type"), "extinguish", "100 is 50 above 50")


func test_the_search_is_limited() -> void:
	var ship := Fixture.room_ship()
	for x in range(10, 21, 2):
		for y in [10, 12, 14]:
			ship.fires[Vector2i(x, y)] = 0.5
	var crew := [_npc("A", 9, 9), _npc("B", 20, 15), _npc("C", 14, 12), _npc("D", 9, 15), _npc("E", 20, 9), _npc("F", 12, 12)]
	ship.crew.append_array(crew)
	var jobs := Jobs.new()
	jobs.tick(ship, STEP)
	check(jobs.paths_used > 0, "it searched")
	eq(jobs.paths_used, int(Jobs.jcfg()["search"]["paths"]), "and stopped at the budget of path searches")
	check(crew.filter(func(m): return not m.job.is_empty()).size() >= 3, "while the first few have work")


# --- the work itself -----------------------------------------------------------------------------

func test_a_crew_member_next_to_a_fire_lowers_it_half_a_point_a_second() -> void:
	var ship := Fixture.room_ship()
	ship.fires[Vector2i(15, 12)] = 0.9
	ship.crew.append(_npc("A", 16, 12))
	var jobs := Jobs.new()
	_run(jobs, ship, 1.0)
	near(ship.fires[Vector2i(15, 12)], 0.4, "0.9 - 0.5 after a second", 1e-5)


func test_two_crew_put_a_fire_out_twice_as_fast() -> void:
	var one := Fixture.room_ship()
	one.fires[Vector2i(15, 12)] = 0.9
	one.crew.append(_npc("A", 16, 12))
	var two := Fixture.room_ship()
	two.fires[Vector2i(15, 12)] = 0.9
	two.crew.append_array([_npc("A", 16, 12), _npc("B", 13, 12)])
	var t1 := _time_until(Jobs.new(), one, func(): return one.fires.is_empty())
	var t2 := _time_until(Jobs.new(), two, func(): return two.fires.is_empty())
	check(t1 > 0.0 and t2 > 0.0, "both put it out")
	near(t1, 1.8, "alone: 0.9 / 0.5", 0.15)
	near(t2, 0.9, "together: 0.9 / 1.0", 0.15)
	check(t2 < t1 * 0.6, "twice as fast")
	check(_log_index(two, "Fire out") >= 0, "and the chronicle says so")


func test_a_crew_member_does_not_stand_in_the_flames_to_fight_them() -> void:
	var ship := Fixture.room_ship()
	for c in [Vector2i(15, 12), Vector2i(16, 12), Vector2i(15, 13), Vector2i(16, 13)]:
		ship.fires[c] = 0.9
	var m := _npc("A", 9, 9)
	ship.crew.append(m)
	var jobs := Jobs.new()
	jobs.tick(ship, STEP)
	check(m.job.has("spot"), "she has a job")
	for c in Pathfinder.body_cells(m.job["spot"]):
		check(not ship.fires.has(c), "the spot %s is clear of fire" % str(m.job["spot"]))


func test_breach_repair_restores_the_wall_and_reseals_the_room() -> void:
	var ship := Fixture.room_ship()
	var room := ship.atmosphere.room_at(Vector2i(15, 9))
	check(ship.atmosphere.rooms[room]["sealed"], "sealed at first")
	ship.grid.breach(Vector2i(15, 8))
	ship.mark_dirty()
	ship.refresh()
	check(not ship.atmosphere.rooms[ship.atmosphere.room_at(Vector2i(15, 9))]["sealed"], "the breach opens the room to space")
	ship.crew.append(_npc("A", 14, 9))
	var jobs := Jobs.new()
	var work := _secs("repair_breach")
	_run(jobs, ship, work - 0.5)
	check(ship.grid.breached.has(Vector2i(15, 8)), "not done at %.1f s (%.0f s of work)" % [work - 0.5, work])
	_run(jobs, ship, 1.0)
	eq(ship.grid.get_tile(Vector2i(15, 8)), "wall", "the wall is back")
	check(ship.grid.breached.is_empty(), "no breach left")
	ship.refresh()
	check(ship.atmosphere.rooms[ship.atmosphere.room_at(Vector2i(15, 9))]["sealed"], "and the room is sealed again")
	check(_log_index(ship, "Breach sealed") >= 0, "'Breach sealed' in the chronicle")
	near(ship.grid.hp_of(Vector2i(15, 8)), 4.0, "at full hp")


func test_a_breach_in_scrap_plate_is_patched_in_half_the_time() -> void:
	var ship := Fixture.room_ship()
	ship.grid.force_tile(Vector2i(15, 8), "scrap_plate")
	ship.grid.breach(Vector2i(15, 8))
	ship.mark_dirty()
	ship.crew.append(_npc("A", 14, 9))
	var t := _time_until(Jobs.new(), ship, func(): return ship.grid.breached.is_empty())
	near(t, _secs("repair_breach") * 0.5, "the breach time x the scrap line's 0.5", 0.15)
	eq(ship.grid.get_tile(Vector2i(15, 8)), "scrap_plate", "the same material comes back")


func test_part_repair_respects_the_lines_repair_multiplier() -> void:
	for pair in [["engine_scrap_mk1", 0.5 * _secs("repair_component")], ["engine_mk1", _secs("repair_component")], ["engine_neon_mk1", 1.5 * _secs("repair_component")]]:
		var ship := Fixture.room_ship()
		var uid := Fixture.put(ship, pair[0], 15, 10)
		var inst: Dictionary = ship.components.instances[uid]
		inst["status"] = "malfunction"
		inst["hp"] = 1
		ship.crew.append(_npc("A", 13, 10))
		var t := _time_until(Jobs.new(), ship, func(): return inst["status"] == "ok")
		near(t, pair[1], "%s takes the part repair time x the repair multiplier" % pair[0], 0.15)
		eq(inst["hp"], ship.effective(pair[0])["hp"], "and comes back at full hp")
	var named := Fixture.room_ship()
	var kick := Fixture.put(named, "engine_scrap_mk1", 15, 10)
	named.components.instances[kick]["status"] = "disabled"
	named.crew.append(_npc("A", 13, 10))
	_time_until(Jobs.new(), named, func(): return named.components.instances[kick]["status"] == "ok")
	check(_log_index(named, "Kickjet repaired") >= 0, "'Kickjet repaired' in the chronicle")


func test_the_crew_walk_to_the_job() -> void:
	var ship := Fixture.room_ship()
	var uid := Fixture.put(ship, "engine_mk1", 15, 14)
	ship.components.instances[uid]["status"] = "malfunction"
	var m := _npc("A", 9, 9)
	ship.crew.append(m)
	var jobs := Jobs.new()
	_run(jobs, ship, 1.0)
	check(m.pos.distance_to(Pathfinder.centre_of(Vector2i(9, 9))) > 2.0, "she is on her way")
	check(jobs.progress.get("fix:%d" % uid, 0.0) == 0.0, "no work done while walking")
	_run(jobs, ship, 3.0)
	check(Jobs.new().in_reach(m, jobs.board["fix:%d" % uid]), "she arrived next to the engine")


# --- the player ----------------------------------------------------------------------------------

func test_the_player_is_never_given_a_job() -> void:
	var ship := Fixture.room_ship()
	var uid := Fixture.put(ship, "engine_mk1", 15, 14)
	ship.components.instances[uid]["status"] = "malfunction"
	ship.fires[Vector2i(12, 12)] = 0.5
	Fixture.put(ship, "helm", 19, 10)
	var p := _player(13, 12)
	ship.crew.append(p)
	var at := p.pos
	var jobs := Jobs.new()
	_run(jobs, ship, 10.0)
	check(p.job.is_empty(), "no job")
	eq(p.pos, at, "and he has not moved")
	check(p.path.is_empty(), "no path")
	check(ship.fires.has(Vector2i(12, 12)), "the fire is still burning")
	check(ship.manned.is_empty(), "and the helm is empty")


func test_the_player_works_a_job_by_hand_at_the_same_speed() -> void:
	var ship := Fixture.room_ship()
	var uid := Fixture.put(ship, "engine_mk1", 15, 14)
	ship.components.instances[uid]["status"] = "malfunction"
	ship.fires[Vector2i(12, 12)] = 0.9
	var p := _player(13, 12)  # next to the fire, far from the engine
	ship.crew.append(p)
	var jobs := Jobs.new()
	jobs.build_board(ship)
	eq(jobs.hand_work(ship, p, 1.0), "fire:12,12", "E held next to the fire")
	near(ship.fires[Vector2i(12, 12)], 0.4, "0.5 a second, like a crew member")
	jobs.hand_work(ship, p, 1.0)
	check(ship.fires.is_empty(), "out")
	p.pos = Pathfinder.centre_of(Vector2i(13, 14))
	jobs.build_board(ship)
	var work := _secs("repair_component")
	for i in roundi(work / STEP) - 1:
		jobs.hand_work(ship, p, STEP)
	eq(ship.components.instances[uid]["status"], "malfunction", "%.1f s is not enough for a standard engine" % (work - STEP))
	for i in 3:
		jobs.hand_work(ship, p, STEP)
	eq(ship.components.instances[uid]["status"], "ok", "%.0f s is" % work)
	eq(jobs.hand_work(ship, p, 1.0), "", "nothing left in reach")


func test_the_player_and_a_crew_member_stack() -> void:
	var ship := Fixture.room_ship()
	ship.fires[Vector2i(15, 12)] = 0.9
	var p := _player(13, 12)  # the other side of the fire from the crew member
	ship.crew.append_array([p, _npc("A", 16, 12)])
	var jobs := Jobs.new()
	for i in 9:
		jobs.tick(ship, STEP)
		jobs.hand_work(ship, p, STEP)
	check(ship.fires.is_empty(), "0.9 gone in 0.9 s: 0.5 + 0.5 a second")


# --- health --------------------------------------------------------------------------------------

func test_fire_hurts_crew_standing_in_it() -> void:
	var ship := Fixture.room_ship()
	ship.fires[Vector2i(15, 12)] = 0.5
	var p := _player(14, 11)  # the body covers (14..15, 11..12): the fire is under it
	var safe := _player(19, 14)
	ship.crew.append_array([p, safe])
	var jobs := Jobs.new()
	jobs.tick(ship, 1.0)
	near(p.hp, 90.0, "10 a second")
	near(safe.hp, 100.0, "the one away from it is fine")


func test_thin_air_hurts_below_15_percent() -> void:
	var ship := Fixture.room_ship()
	var p := _player(14, 11)
	ship.crew.append(p)
	var room := ship.atmosphere.room_at(p.cell())
	var jobs := Jobs.new()
	ship.atmosphere.pressure[room] = 0.15
	jobs.tick(ship, 1.0)
	near(p.hp, 100.0, "15% is fine")
	ship.atmosphere.pressure[room] = 0.14
	jobs.tick(ship, 1.0)
	near(p.hp, 95.0, "below it: 5 a second")


func test_at_zero_a_crew_member_is_down_and_stays_where_they_are() -> void:
	var ship := Fixture.room_ship()
	ship.fires[Vector2i(15, 12)] = 0.5
	var p := _player(14, 11)
	ship.crew.append(p)
	var jobs := Jobs.new()
	for i in 12:
		jobs.tick(ship, 1.0)
	check(p.is_down(), "down")
	near(p.hp, 0.0, "hp stops at 0")
	check(_log_index(ship, "Soldier is down") >= 0, "the chronicle says so")
	var at := p.pos
	p.move_input(ship.grid, Vector2.RIGHT, 1.0)
	eq(p.pos, at, "he does not walk")
	var n := _npc("A", 10, 10)
	n.hurt(1000.0)
	check(n.is_down(), "an NPC too")
	n.go_to(ship.grid, Vector2i(18, 14))
	n.step(1.0)
	eq(n.pos, Pathfinder.centre_of(Vector2i(10, 10)), "does not move")


func test_a_crewmate_revives_a_downed_crew_member() -> void:
	var ship := Fixture.room_ship()
	var p := _player(18, 14)
	p.hurt(1000.0)
	var n := _npc("Ada", 10, 10)
	ship.crew.append_array([p, n])
	var jobs := Jobs.new()
	jobs.tick(ship, STEP)
	eq(jobs.board["revive:Soldier"]["priority"], 95, "a downed crewmate is a job")
	eq(n.job.get("key"), "revive:Soldier", "Ada goes to him")
	var t := _time_until(jobs, ship, func(): return not p.is_down())
	check(t > 3.0, "it takes 3 s of work and a walk: %s" % t)
	near(p.hp, 20.0, "he comes back with 20 hp")
	check(_log_index(ship, "Soldier is back on their feet") >= 0, "the chronicle says so")


func _medbay_ship(power: bool) -> Dictionary:
	var ship := Fixture.room_ship()
	var d := {"ship": ship}
	d["medbay"] = Fixture.put(ship, "medbay", 10, 10)  # x 10..11, y 10..13: one bed
	if power:
		Fixture.put(ship, "reactor_mk1", 15, 10)  # x 15..16, y 10..13
		Fixture.wire(ship, [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	return d


func test_a_powered_medbay_heals_15_a_second_and_brings_the_downed_back() -> void:
	var d := _medbay_ship(true)
	var ship: Ship = d["ship"]
	var p := _player(10, 10)  # the body centre is in the medbay
	p.hurt(1000.0)
	ship.crew.append(p)
	var jobs := Jobs.new()
	jobs.tick(ship, 1.0)
	near(p.hp, 15.0, "15 a second")
	check(not p.is_down(), "up again")
	check(_log_index(ship, "Soldier is back on their feet") >= 0, "the chronicle says so")
	jobs.tick(ship, 10.0)
	near(p.hp, 100.0, "healed")


func test_a_medbay_in_a_room_with_no_air_heals_nobody_who_breathes() -> void:
	var d := _medbay_ship(true)
	var ship: Ship = d["ship"]
	var p := _player(10, 10)
	p.hurt(50.0)
	ship.crew.append(p)
	var jobs := Jobs.new()
	near(jobs._heal_rate(ship, p), 15.0, "(setup) with air the medbay heals 15 a second")
	var room: int = ship.atmosphere.room_at(p.cell())
	ship.atmosphere.pressure[room] = 0.0
	near(jobs._heal_rate(ship, p), 0.0, "with its room empty it heals nobody who breathes (the bed's rule, fixes4)")
	ship.atmosphere.pressure[room] = 0.14
	near(jobs._heal_rate(ship, p), 0.0, "and just under no_air_below")
	ship.atmosphere.pressure[room] = 0.16
	near(jobs._heal_rate(ship, p), 15.0, "it heals again just over it")
	ship.atmosphere.pressure[room] = 0.0
	p.equip("suit")
	near(jobs._heal_rate(ship, p), 15.0, "a suit wearer cannot suffocate and is still healed, as on a bed")


func test_an_unpowered_medbay_does_nothing() -> void:
	var d := _medbay_ship(false)
	var ship: Ship = d["ship"]
	var p := _player(10, 10)
	p.hurt(50.0)
	ship.crew.append(p)
	Jobs.new().tick(ship, 1.0)
	near(p.hp, 50.0, "no power, no healing")


func test_a_bed_heals_5_a_second() -> void:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "bed", 10, 10)  # x 10..11, y 10..13
	var p := _player(10, 10)
	p.hurt(50.0)
	ship.crew.append(p)
	Jobs.new().tick(ship, 2.0)
	near(p.hp, 60.0, "5 a second")


func test_a_hurt_crew_member_with_nothing_to_do_goes_to_bed() -> void:
	var ship := Fixture.room_ship()
	var bed := Fixture.put(ship, "bed", 10, 10)
	var m := _npc("Ada", 18, 14)
	m.hurt(40.0)
	ship.crew.append(m)
	var jobs := Jobs.new()
	jobs.tick(ship, STEP)
	eq(m.job.get("type"), "rest", "she rests")
	eq(m.job.get("key"), "rest:%d" % bed, "on the bed")
	var t := _time_until(jobs, ship, func(): return m.hp >= m.max_hp)
	check(t > 0.0, "healed to full: %s" % t)
	_run(jobs, ship, 2.0)
	check(m.job.is_empty(), "and she gets up")


func test_a_powered_medbay_is_preferred_over_a_bed() -> void:
	var d := _medbay_ship(true)
	var ship: Ship = d["ship"]
	Fixture.put(ship, "bed", 19, 10)
	var m := _npc("Ada", 17, 14)  # nearer to the bed
	m.hurt(40.0)
	ship.crew.append(m)
	var jobs := Jobs.new()
	jobs.tick(ship, STEP)
	eq(m.job.get("key"), "rest:%d" % d["medbay"], "the medbay")


func test_a_medbay_is_one_bed_it_heals_one_crew_member_at_a_time() -> void:
	var d := _medbay_ship(true)
	var ship: Ship = d["ship"]
	eq(ship.components.def("medbay")["size"], [2, 4], "a 2x4 bay")
	var a := _npc("Ada", 10, 10)  # both bodies lie on the medbay (a 2x2 body fits twice in 2x4)
	var b := _npc("Bram", 10, 12)
	a.hurt(50.0)
	b.hurt(50.0)
	ship.crew.append(a)
	ship.crew.append(b)
	check(ship.components.instances[d["medbay"]]["cells"].has(a.cell()) and ship.components.instances[d["medbay"]]["cells"].has(b.cell()), "(setup: both lie in it)")
	var jobs := Jobs.new()
	jobs.tick(ship, 1.0)
	near(a.hp, 65.0, "the first one heals 15 a second")
	near(b.hp, 50.0, "the second heals nothing there")
	jobs.tick(ship, 1.0)
	near(b.hp, 50.0, "and keeps waiting while the first is on it")
	jobs.tick(ship, 10.0)
	near(a.hp, 100.0, "the first is whole")
	jobs.tick(ship, 1.0)
	near(b.hp, 65.0, "then the medbay takes the second")


func test_a_second_hurt_crew_member_goes_to_a_bed_when_the_medbay_is_taken() -> void:
	var d := _medbay_ship(true)
	var ship: Ship = d["ship"]
	var bed := Fixture.put(ship, "bed", 19, 10)
	var a := _npc("Ada", 17, 14)
	var b := _npc("Bram", 17, 12)
	a.hurt(40.0)
	b.hurt(40.0)
	ship.crew.append(a)
	ship.crew.append(b)
	var jobs := Jobs.new()
	jobs.tick(ship, STEP)
	eq(a.job.get("key"), "rest:%d" % d["medbay"], "the first takes the medbay")
	eq(b.job.get("key"), "rest:%d" % bed, "the second, with the medbay claimed, takes the bed")


func test_a_manual_order_keeps_the_job_board_away_for_a_while() -> void:
	var ship := Fixture.room_ship()
	ship.fires[Vector2i(12, 12)] = 0.9
	var m := _npc("Ada", 13, 12)
	ship.crew.append(m)
	check(Jobs.order_move(ship, m, Vector2i(18, 14)), "there is a way")
	var jobs := Jobs.new()
	_run(jobs, ship, 3.0)
	near(ship.fires[Vector2i(12, 12)], 0.9, "she walks on, the fire is not touched")
	eq(m.anchor(), Vector2i(18, 14), "and arrives")
	_run(jobs, ship, 14.0)
	check(ship.fires.is_empty(), "then the board has her again")


func test_an_order_repairs_a_damaged_part_that_still_works() -> void:
	var ship := Fixture.room_ship()
	var uid := Fixture.put(ship, "engine_mk1", 15, 10)
	var inst: Dictionary = ship.components.instances[uid]
	inst["hp"] = 2
	var jobs := Jobs.new()
	jobs.build_board(ship)
	check(not jobs.board.has("fix:%d" % uid), "the board leaves it alone")
	eq(jobs.order_repair(ship, uid), "no crew to send", "nobody to send")
	ship.crew.append(_npc("Ada", 13, 10))
	eq(jobs.order_repair(ship, uid), "Ada will repair Concord Thruster Mk1", "an order does")
	_run(jobs, ship, _secs("repair_component") + 3.0)  # the walk there, then the work
	eq(inst["hp"], 6, "mended")
	eq(jobs.order_repair(ship, uid), "Concord Thruster Mk1 needs no repair", "nothing more to do")
	inst["status"] = "overheated"
	eq(jobs.order_repair(ship, uid), "Concord Thruster Mk1 is cooling down", "an overheated part just needs time")
	eq(jobs.order_repair(ship, 99), "no system under the mouse", "no such part")


# --- manned bonuses ------------------------------------------------------------------------------

func test_a_manned_helm_adds_evasion() -> void:
	var ship := Fixture.room_ship()
	var helm := Fixture.put(ship, "helm", 19, 10)
	eq(Jobs.evasion_bonus(ship), 0.0, "nobody at the helm")
	ship.crew.append(_npc("Ada", 13, 14))
	var jobs := Jobs.new()
	_run(jobs, ship, 8.0)
	check(ship.manned.has(helm), "she went to the helm on her own")
	near(Jobs.evasion_bonus(ship), 0.05, "+5 percent")
	ship.components.instances[helm]["status"] = "malfunction"
	eq(Jobs.evasion_bonus(ship), 0.0, "a broken helm gives nothing")


func _gun_ship(manned: bool) -> Dictionary:
	var ship := Fixture.room_ship()
	var reactor := Fixture.put(ship, "reactor_mk1", 10, 10)
	var laser := Fixture.put(ship, "laser_mk1", 15, 10)
	Fixture.wire(ship, [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.components.by_id["laser_mk1"]["manned"] = true
	ship.refresh()
	if manned:
		ship.crew.append(_npc("Ada", 15, 12))
		_run(Jobs.new(), ship, 3.0)
	return {"ship": ship, "laser": laser, "reactor": reactor}


func test_a_manned_weapon_cools_down_ten_percent_faster() -> void:
	var cooldowns := []
	for manned in [false, true]:
		var d := _gun_ship(manned)
		check(d["ship"].manned.has(d["laser"]) == manned, "the laser is manned: %s" % str(manned))
		var a := Arena.new()
		var i := a.add_ship(d["ship"])
		check(a.fire(i, d["laser"], Vector2(0.0, -1000.0)), "it fires")
		cooldowns.append(a.cooldown_left(i, d["laser"]))
	near(cooldowns[0], 2.1, "alone: the data's 2.1 s", 0.02)
	near(cooldowns[1], 1.89, "manned: 10 percent less", 0.03)
	check(cooldowns[1] < cooldowns[0], "shorter")


func test_a_manned_weapon_fires_again_sooner() -> void:
	var d := _gun_ship(true)
	var a := Arena.new()
	var i := a.add_ship(d["ship"])
	var aim := Vector2(0.0, -1000.0)
	check(a.fire(i, d["laser"], aim), "first shot")
	a.step(1.85)
	check(not a.fire(i, d["laser"], aim), "still cooling at 1.85 s")
	a.step(0.06)
	check(a.fire(i, d["laser"], aim), "ready at 1.91 s, before the unmanned 2.1 s")


# --- crews ---------------------------------------------------------------------------------------

func test_the_starters_start_with_the_soldier_alone() -> void:
	for path in STARTERS:
		var ship := Ship.from_design(path)
		eq(ship.crew_plan, [{"name": "Soldier", "species": "human"}], path + ": the design lists the soldier alone")
		var made := Jobs.spawn_crew(ship)
		eq(made.size(), 1, path + ": one person made")
		check(ship.crew[0].is_player and ship.crew.size() == 1, path + ": the soldier is the only one aboard")
		check(Pathfinder.body_ok(ship.grid, ship.crew[0].anchor()), path + ": and stands where a body fits")


func test_a_design_with_a_crew_list_spawns_it_round_the_beds() -> void:
	for path in STARTERS:
		var ship := Ship.from_design(path)
		ship.crew_plan = TEAM.duplicate(true)
		var want: Array = ship.crew_plan.map(func(e): return e["name"])
		var made := Jobs.spawn_crew(ship)
		check(want.size() >= 3, path + ": the design lists a crew")
		eq(made.size(), want.size(), path + ": the whole crew list")
		eq(ship.crew.size(), want.size(), path + ": all aboard")
		eq(ship.crew.filter(func(m): return m.is_player).size(), 1, path + ": one of them is the player")
		var names: Array = ship.crew.map(func(m): return m.name)
		eq(names, want, path + ": the names of the list, in order")
		check(names.has("Soldier"), path + ": the soldier")
		eq(_distinct(names), want.size(), path + ": names are all different")
		eq(_distinct(ship.crew.map(func(m): return m.look["suit"])), want.size(), path + ": different suits")
		for m in ship.crew:
			check(Pathfinder.body_ok(ship.grid, m.anchor()), "%s: %s stands where a body fits" % [path, m.name])
		for i in ship.crew.size():
			for j in range(i + 1, ship.crew.size()):
				var a: Vector2i = ship.crew[i].anchor()
				var b: Vector2i = ship.crew[j].anchor()
				check(absi(a.x - b.x) >= 2 or absi(a.y - b.y) >= 2, "%s: %s and %s do not overlap" % [path, ship.crew[i].name, ship.crew[j].name])
		var beds: Array = []
		for uid in ship.components.instances:
			if ship.components.def(ship.components.instances[uid]["id"])["family"] == "bed":
				beds.append(ship.components.instances[uid]["cells"])
		var first: Array = ship.crew.filter(func(m): return not m.is_player and m.name != "Ada")
		check(beds.any(func(cells): return cells.has(first[0].cell())), "%s: %s starts on a bed (the others beside it: the ship has one)" % [path, first[0].name])
		eq(Jobs.spawn_crew(ship).size(), 0, path + ": asking again adds nobody")
		eq(ship.crew.size(), want.size(), path + ": still the same crew")


func test_a_design_with_no_crew_list_gets_the_default_crew() -> void:
	var ship := Ship.from_design(STARTERS[0])
	ship.crew_plan = []
	var made := Jobs.spawn_crew(ship)
	eq(made.map(func(m): return m.name), ["Soldier", "Ada", "Rook", "Juno"], "the soldier, Ada and the first two names")
	check(made.all(func(m): return m.species == "human"), "all human, as before")


func test_no_floor_no_crew_yet() -> void:
	var ship := Ship.new_starter()
	eq(Jobs.spawn_crew(ship).size(), 0, "nowhere to stand on the bare hull")
	check(ship.crew.is_empty(), "nobody aboard")


func test_the_pirate_has_three_enemy_crew() -> void:
	var ship := Ship.from_design(PIRATE)
	var made := Jobs.spawn_enemy_crew(ship)
	eq(made.size(), 3, "three")
	check(made.all(func(m): return not m.is_player and Pathfinder.body_ok(ship.grid, m.anchor())), "ordinary crew on the floor")
	check(made.all(func(m): return m.look == made[0].look), "in the enemy colours")
	eq(_distinct(made.map(func(m): return m.name)), 3, "with three names")
	var sim := ShipSim.new()
	var player := Ship.from_design(STARTERS[1])
	sim.ships = [player, Ship.from_design(PIRATE)]
	sim.step(0.1)
	eq(sim.ships[1].crew.size(), 3, "the sim crews the other ship on its first tick")
	eq(player.crew.size(), 0, "and leaves the player's to the crew view")
	sim.step(0.1)
	eq(sim.ships[1].crew.size(), 3, "once")
	sim.free()


func test_the_crew_keep_working_during_a_fight() -> void:
	var sim := ShipSim.new()
	var ship := Fixture.room_ship()
	var uid := Fixture.put(ship, "laser_mk1", 15, 10)
	ship.components.instances[uid]["status"] = "malfunction"
	ship.fires[Vector2i(12, 12)] = 0.5
	ship.crew.append_array([_npc("Ada", 9, 13), _npc("Rook", 18, 14)])
	var enemy := Ship.from_design(PIRATE)
	sim.ships = [ship, enemy]  # two ships in the sim: a fight
	sim.step(0.1)
	check(sim.jobs_of(ship).combat, "the board knows it is a fight")
	eq(sim.jobs_of(ship).board["fix:%d" % uid]["priority"], 90, "a weapon is a 90 job in a fight")
	for i in 400:
		sim.step(0.1)
	check(ship.fires.is_empty(), "the fire is out")
	eq(ship.components.instances[uid]["status"], "ok", "and the laser is mended")
	check(enemy.crew.size() == 3, "the pirate's crew are at their posts")
	sim.free()


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func test_holding_e_next_to_a_fire_puts_it_out() -> void:
	var sim := ShipSim.new()
	var ship := Fixture.room_ship()
	sim.ships = [ship]
	var view := CrewView.new()
	view.sim = sim
	view.build = BuildMode.new()
	view.build.sim = sim
	view.build.build_on = false  # play mode: build mode pauses the world
	var p := _player(13, 12)
	ship.crew.append(p)
	view.player = p
	view.ada = _npc("Ada", 20, 14)  # (so the view does not spawn a crew of its own)
	ship.crew.append(view.ada)
	ship.fires[Vector2i(15, 12)] = 0.9
	sim.step(0.1)  # the board is built
	var before: float = ship.fires[Vector2i(15, 12)]
	view._process(0.5)
	near(ship.fires[Vector2i(15, 12)], before, "E not held: nothing happens")
	_key(KEY_E, true)
	for i in 4:
		view._process(0.25)
	_key(KEY_E, false)
	near(ship.fires[Vector2i(15, 12)], before - 0.5, "E held for a second: 0.5 less", 0.01)
	check(Jobs.crew_line(ship).contains("You extinguishing"), "the HUD line shows what he is doing: " + Jobs.crew_line(ship))
	view.build.free()
	view.free()
	sim.free()


func test_the_crew_view_spawns_the_crew_and_finds_the_player_and_ada() -> void:
	var view := CrewView.new()
	var ship := Ship.from_design(STARTERS[0])
	ship.crew_plan = TEAM.duplicate(true)
	view._spawn(ship)
	eq(ship.crew.size(), 4, "four aboard")
	check(view.player != null and view.player.is_player, "the player's soldier")
	eq(view.ada.name, "Ada", "and Ada")
	var count: int = ship.crew.size()
	view._spawn(ship)
	eq(ship.crew.size(), count, "nothing is added twice")
	var other := Ship.from_design(STARTERS[1])
	other.crew_plan = TEAM.slice(0, 3).duplicate(true)
	view._spawn(other)
	eq(other.crew.size(), 3, "a new ship gets its own crew")
	check(view.player in other.crew and not view.player in ship.crew, "the view follows the new ship's soldier")
	var prism := Ship.from_design(STARTERS[2])  # no Ada on this crew list
	prism.crew_plan = [TEAM[0], {"name": "Tess", "species": "emberkin"}, {"name": "Quill", "species": "fenn"}]
	view._spawn(prism)
	eq(prism.crew.size(), 3, "the three of the list")
	check(view.player in prism.crew and view.ada == null, "a soldier and no Ada")
	view._spawn(prism)
	eq(prism.crew.size(), 3, "and nothing is added twice without her either")
	var alone := Ship.from_design(STARTERS[2])  # the real start: the soldier alone
	view._spawn(alone)
	eq(alone.crew.size(), 1, "the soldier alone")
	check(view.player in alone.crew and view.ada == null, "and no Ada")
	eq(view.order_target(), null, "a middle-click has nobody to send")
	view.free()


func test_a_middle_click_sends_the_selected_crewmate_else_ada_else_the_first_one() -> void:
	var view := CrewView.new()
	var sim := ShipSim.new()
	var ship := Fixture.room_ship()
	sim.ships = [ship]
	view.sim = sim
	view.build = BuildMode.new()
	view.build.sim = sim
	var p := _player(13, 12)
	ship.crew.append(p)
	view.player = p
	eq(view.order_target(), null, "the soldier alone: nobody")
	var rook := _npc("Rook", 20, 14)
	var juno := _npc("Juno", 22, 14)
	ship.crew.append(rook)
	ship.crew.append(juno)
	eq(view.order_target(), rook, "no Ada, nothing selected: the first crewmate who is not the soldier")
	view.selected = juno
	eq(view.order_target(), juno, "the selected crewmate")
	view.selected = p
	eq(view.order_target(), rook, "the soldier is not sent")
	view.selected = null
	var ada := _npc("Ada", 24, 14)
	ship.crew.append(ada)
	view.ada = ada
	eq(view.order_target(), ada, "Ada when she is aboard and nobody is selected")
	view.selected = juno
	eq(view.order_target(), juno, "a selected crewmate before Ada")
	view.build.free()
	view.free()
	sim.free()


# --- the story ---------------------------------------------------------------------------------

func _story(path: String, seconds: int) -> Array:
	var sim := ShipSim.new()
	sim.choose_ship(path)
	var ship: Ship = sim.player_ship()
	Jobs.spawn_crew(ship)
	for i in seconds * 4:
		sim.step(0.25)
	var out: Array = [ship.events.map(func(e): return "%d %s" % [roundi(e["t"]), e["text"]]), ship.fires.duplicate()]
	for m in ship.crew:
		out.append([m.name, m.pos, m.hp, m.job.get("key", ""), ship.atmosphere.room_at(m.cell())])
	for uid in ship.components.instances:
		var inst: Dictionary = ship.components.instances[uid]
		out.append([uid, inst["status"], inst["hp"], roundf(inst["heat"] * 1000.0)])
	sim.free()
	return out


func test_the_same_ship_plays_out_the_same() -> void:
	var a := _story(STARTERS[0], 320)  # the Rustbucket: its scrap parts break and burn
	var b := _story(STARTERS[0], 320)
	eq(a, b, "the same seed, the same story")
	check(a[0].size() > 3, "and there was one to tell: %s" % str(a[0]))


func test_crew_line_reads_like_the_hud_example() -> void:
	var ship := Fixture.room_ship()
	var ada := _npc("Ada", 10, 10)
	ada.job = {"label": Jobs.label_of({"type": "repair_component", "name": "Laser Mk1"})}
	var rook := _npc("Rook", 12, 10)
	rook.job = {"label": Jobs.label_of({"type": "extinguish"})}
	var juno := _npc("Juno", 14, 10)
	juno.job = {"label": Jobs.label_of({"type": "man_station", "family": "helm", "name": "Helm"})}
	var pike := _npc("Pike", 16, 10)
	var me := _player(18, 10)
	ship.crew.append_array([ada, rook, juno, pike, me])
	eq(Jobs.crew_line(ship), "Crew: Ada repairing Laser Mk1, Rook extinguishing, Juno at helm, Pike idle", "the player is left out while fine")
	me.hurt(30.0)
	eq(Jobs.crew_line(ship), "Crew: Ada repairing Laser Mk1, Rook extinguishing, Juno at helm, Pike idle, You hurt (70 hp)", "and named when hurt")
	pike.hurt(1000.0)
	check(Jobs.crew_line(ship).contains("Pike down"), "a downed one says so")
	eq(Jobs.crew_line(Fixture.room_ship()), "Crew: none", "an empty ship")


func test_crew_with_the_right_traits_take_the_station_that_needs_them() -> void:
	var ship := Fixture.room_ship()
	var burner := Fixture.put(ship, "afterburner", 15, 14)
	var helm := Fixture.put(ship, "helm", 19, 10)
	var ada := _npc("Ada", 15, 12)  # closer to the afterburner, but no suit
	var rook := _npc("Rook", 18, 12)  # has the "suit" trait in data/crew.json
	ship.crew.append(ada)
	ship.crew.append(rook)
	var jobs := Jobs.new()
	_run(jobs, ship, 1.5)
	eq(rook.job.get("key"), "post:%d" % burner, "the suited crew member mans the afterburner")
	eq(ada.job.get("key"), "post:%d" % helm, "and the other takes the helm")


func test_a_breach_in_a_mount_wall_is_worked_from_beside_the_mount() -> void:
	for path in STARTERS:
		var ship := Ship.from_design(path)
		ship.crew_plan = TEAM.duplicate(true)
		var link: Array = []
		var uids: Array = ship.components.instances.keys()
		uids.sort()
		for uid in uids:
			if not ship.components.instances[uid]["link"].is_empty():
				link = ship.components.instances[uid]["link"]
				break
		check(not link.is_empty(), path + ": a hull mount with a wall between its halves")
		if link.is_empty():
			continue
		var cell: Vector2i = link[0]
		ship.grid.breach(cell)
		ship.mark_dirty()
		ship.refresh()
		var view := CrewView.new()
		view._spawn(ship)
		view.free()
		var jobs := Jobs.new()
		jobs.build_board(ship)
		var job: Dictionary = jobs.board["breach:%d,%d" % [cell.x, cell.y]]
		check(job.has("reach"), path + ": the breach job knows the mount it runs through")
		check(not jobs.stand_spots(ship, job).is_empty(), path + ": somewhere to stand to work it")
		_run(jobs, ship, 40.0)
		check(not ship.grid.breached.has(cell), path + ": the crew seal it")


func test_a_breach_beside_a_mount_wall_is_worked_from_beside_the_mount_too() -> void:
	var tried := 0
	for path in STARTERS:
		var ship := Ship.from_design(path)
		ship.crew_plan = TEAM.duplicate(true)
		var uids: Array = ship.components.instances.keys()
		uids.sort()
		var cell := Vector2i(-1, -1)
		for uid in uids:
			var link: Array = ship.components.instances[uid]["link"]
			for l in link:
				for side in [Vector2i.LEFT, Vector2i.RIGHT]:
					var n: Vector2i = l + side
					if not link.has(n) and ship.grid.tile_flag(ship.grid.get_tile(n), "solid") and ship.components.at(n) < 0:
						cell = n
						break
				if cell.x >= 0:
					break
			if cell.x >= 0:
				break
		if cell.x < 0:
			continue
		tried += 1
		ship.grid.breach(cell)
		ship.mark_dirty()
		ship.refresh()
		var view := CrewView.new()
		view._spawn(ship)
		view.free()
		var jobs := Jobs.new()
		jobs.build_board(ship)
		var job: Dictionary = jobs.board["breach:%d,%d" % [cell.x, cell.y]]
		check(not jobs.stand_spots(ship, job).is_empty(), "%s: somewhere to stand by the breach at %s" % [path, cell])
		_run(jobs, ship, 40.0)
		check(not ship.grid.breached.has(cell), "%s: the crew seal the breach at %s" % [path, cell])
	check(tried > 0, "a starter has a wall cell beside a mount's wall")
