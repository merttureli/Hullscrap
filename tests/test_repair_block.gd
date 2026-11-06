extends "res://tests/base_test.gd"
## The repair_block job (data/crew.json `jobs`, scripts/crew/jobs.gd): every wall or door below its hp that is not breached is
## something to go and mend, by the crew, the drones and the soldier's hand (E). Priority 60 in a fight and 65 out of one, below every
## other repair; the work is by the hp missing, times the tile line's repair multiplier. The wrench in the top bar clears as they go.

const Fixture = preload("res://tests/fixture_ship.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Ship = preload("res://scripts/ship/ship.gd")

const STEP := 0.1
const WALL := Vector2i(15, 8)  ## a wall of the room ship's north side


func _human(ship: Ship, p_name: String, x: int, y: int, player := false) -> CrewMember:
	var m := CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)))
	m.is_player = player
	ship.crew.append(m)
	return m


func _drone(ship: Ship, x: int, y: int) -> CrewMember:
	var m := CrewMember.new("Drone", Pathfinder.centre_of(Vector2i(x, y), 1), "drone")
	ship.crew.append(m)
	return m


func _ship() -> Ship:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "reactor_mk1", 10, 10)
	Fixture.wire(ship, [Vector2i(10, 10)])
	ship.refresh()
	return ship


func _run(jobs: Jobs, ship: Ship, seconds: float) -> void:
	for i in roundi(seconds / STEP):
		ship.refresh()
		jobs.tick(ship, STEP)


func test_a_damaged_wall_is_a_job_and_a_breach_is_not() -> void:
	var ship := _ship()
	ship.grid.hp[WALL] = 1.0  # 3 of 4 hp gone
	ship.grid.breach(Vector2i(16, 8))
	var jobs := Jobs.new()
	jobs.build_board(ship)
	check(jobs.board.has("block:15,8"), "the damaged wall is on the board")
	check(jobs.board.has("breach:16,8") and not jobs.board.has("block:16,8"), "a breach stays a breach job")
	var job: Dictionary = jobs.board["block:15,8"]
	eq(job["type"], "repair_block", "its type")
	eq(job["priority"], 65, "65 out of a fight")
	near(float(job["work"]), 1.5 * 3.0, "1.5 s for each hp missing")
	jobs.combat = true
	jobs.build_board(ship)
	eq(jobs.board["block:15,8"]["priority"], 60, "60 in a fight")
	check(60 < int(Jobs.jcfg()["repair_belt"]["priority"]) and 60 < int(Jobs.jcfg()["repair_crew"]["priority"]) and 60 < int(Jobs.jcfg()["repair_component"]["priority"]) and 60 < int(Jobs.jcfg()["repair_breach"]["priority"]), "below every other repair")
	check(60 > int(Jobs.jcfg()["man_station"]["priority"]), "above manning a station")
	var fine := _ship()
	var j2 := Jobs.new()
	j2.build_board(fine)
	check(not j2.board.keys().any(func(k): return str(k).begins_with("block:")), "a sound ship has none")


func near(got: float, want: float, msg: String) -> void:
	check(absf(got - want) < 1e-6, "%s: expected %s, got %s" % [msg, want, got])


func test_the_work_follows_the_hp_missing_and_the_lines_repair_multiplier() -> void:
	var ship := _ship()
	ship.grid.hp[WALL] = 3.0  # 1 hp
	ship.grid.hp[Vector2i(17, 8)] = 0.5  # 3.5 hp
	var jobs := Jobs.new()
	jobs.build_board(ship)
	near(float(jobs.board["block:15,8"]["work"]), 1.5, "1 hp")
	near(float(jobs.board["block:17,8"]["work"]), 1.5 * 3.5, "3.5 hp")
	var line: String = str(ship.grid.defs.get_def("wall").get("line", "standard"))
	ship.lines = ship.lines.duplicate(true)
	ship.lines[line] = ship.lines.get(line, {}).duplicate()
	ship.lines[line]["repair"] = 2.0
	jobs.build_board(ship)
	near(float(jobs.board["block:15,8"]["work"]), 3.0, "a line that repairs at 2x takes 2x as long")


func test_the_crew_mend_a_damaged_wall_and_the_wrench_clears() -> void:
	var ship := _ship()
	var bob := _human(ship, "Bob", 14, 12)
	var inner := [Vector2i(15, 15), Vector2i(16, 15)]  # crew mend inner walls only (the room's outer wall is the drones')
	for c in inner:
		ship.grid.force_tile(c, "wall")
	ship.refresh()
	ship.grid.hp[inner[0]] = 1.0
	ship.grid.hp[inner[1]] = 2.0
	eq(Structure.damaged(ship).size(), 2, "two damaged blocks: the wrench counts them")
	var jobs := Jobs.new()
	jobs.build_board(ship)
	_run(jobs, ship, 60.0)
	check(not ship.grid.hp.has(inner[0]) and not ship.grid.hp.has(inner[1]), "both walls are mended by the crew")
	eq(ship.grid.hp_of(inner[0]), 4.0, "at full hp")
	eq(Structure.damaged(ship).size(), 0, "and the wrench clears")
	check(bob.job.is_empty() or bob.job["type"] != "repair_block", "nothing left for them")


func test_a_drone_mends_a_damaged_wall() -> void:
	var ship := _ship()
	var d := _drone(ship, 14, 10)
	ship.grid.hp[WALL] = 2.0
	check("repair_block" in CrewMember.config()["drone_jobs"], "it is one of the drone's jobs")
	var jobs := Jobs.new()
	jobs.build_board(ship)
	var seen := false
	for i in roundi(90.0 / STEP):
		ship.refresh()
		jobs.tick(ship, STEP)
		seen = seen or (not d.job.is_empty() and d.job["type"] == "repair_block")
	check(seen, "the drone took the job")
	check(not ship.grid.hp.has(WALL), "and mended the wall")
	eq(Structure.damaged(ship).size(), 0, "no damaged block is left")


func test_the_soldier_mends_a_wall_by_hand_with_e() -> void:
	var ship := _ship()
	var me := _human(ship, "Soldier", 14, 9, true)  # beside the north wall
	ship.grid.hp[WALL] = 2.0  # 2 hp missing: 3 s
	var jobs := Jobs.new()
	jobs.build_board(ship)
	check(jobs.in_reach(me, jobs.board["block:15,8"]), "the wall is in reach")
	eq(jobs.hand_work(ship, me, 1.0), "block:15,8", "holding E beside it works the mending")
	check(ship.grid.hp.has(WALL), "a second is not enough")
	jobs.hand_work(ship, me, 1.0)
	jobs.hand_work(ship, me, 1.1)
	check(not ship.grid.hp.has(WALL), "three seconds of E mend a wall that lost 2 hp")
	eq(jobs.hand_work(ship, me, 1.0), "", "and then there is nothing in reach")


func test_a_part_or_a_breach_comes_before_a_wall() -> void:
	var ship := _ship()
	var bob := _human(ship, "Bob", 14, 12)
	ship.grid.hp[WALL] = 1.0
	ship.grid.breach(Vector2i(20, 8))
	var jobs := Jobs.new()
	jobs.build_board(ship)
	var best: Array = jobs.by_priority(jobs.board.values())
	eq(best[0]["type"], "repair_breach", "the breach first")
	eq(best[-1]["type"], "repair_block", "the wall last of the repairs")
	check(bob != null, "(a crew member is aboard)")
