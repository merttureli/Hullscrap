extends "res://tests/base_test.gd"
## Who repairs what: a repair drone climbs the walls and the outer hull and mends any damaged cell or part; the crew mend inner walls and
## inside parts only; a destroyed part (a wreck) is nobody's to repair (scripts/crew/pathfinder.gd `climb`, jobs.gd `hull` jobs).

const Fixture = preload("res://tests/fixture_ship.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Ship = preload("res://scripts/ship/ship.gd")

const STEP := 0.1
const OUTER := Vector2i(15, 8)  ## a wall of the room ship's north side: open to space on its far side
const INNER := Vector2i(15, 14)


func _ship() -> Ship:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "reactor_mk1", 10, 10)
	Fixture.wire(ship, [Vector2i(10, 10)])
	ship.grid.force_tile(INNER, "wall")
	ship.refresh()
	return ship


func _run(jobs: Jobs, ship: Ship, seconds: float) -> void:
	for i in roundi(seconds / STEP):
		ship.refresh()
		jobs.tick(ship, STEP)


func test_a_climber_walks_over_wall_and_hull_cells_and_a_walker_does_not() -> void:
	var ship := _ship()
	check(not Pathfinder.walkable(ship.grid, OUTER), "a walker cannot stand on a wall")
	check(Pathfinder.walkable(ship.grid, OUTER, Callable(), true), "a climber can")
	check(not Pathfinder.walkable(ship.grid, Vector2i(15, 6), Callable(), true), "but not on empty space")
	var from := Vector2i(15, 10)
	var path := Pathfinder.find_path(ship.grid, from, Vector2i(18, 8), Callable(), 1, true)
	check(not path.is_empty(), "a climber crosses the wall line")
	check(Pathfinder.find_path(ship.grid, from, Vector2i(18, 8), Callable(), 1).is_empty(), "a walker has no way onto the wall")
	# along the outer hull, from the north wall to the west wall, over the corner
	check(not Pathfinder.find_path(ship.grid, Vector2i(10, 8), Vector2i(8, 12), Callable(), 1, true).is_empty(), "and it walks along the hull")


func test_a_drone_reaches_and_mends_a_damaged_outer_hull_cell() -> void:
	var ship := _ship()
	ship.grid.hp[OUTER] = 1.0
	var d := CrewMember.new("Drone", Pathfinder.centre_of(Vector2i(12, 12), 1), "drone")
	ship.crew.append(d)
	var jobs := Jobs.new()
	jobs.build_board(ship)
	check(jobs.board["block:15,8"].get("hull", false), "the outer wall is a hull job")
	_run(jobs, ship, 40.0)
	check(not ship.grid.hp.has(OUTER), "the drone mended it")


func test_a_crew_member_never_takes_the_outer_hull_job_but_mends_an_inner_wall() -> void:
	var ship := _ship()
	ship.grid.hp[OUTER] = 1.0
	var ada := CrewMember.new("Ada", Pathfinder.centre_of(Vector2i(14, 10)))
	ship.crew.append(ada)
	var jobs := Jobs.new()
	_run(jobs, ship, 30.0)
	eq(ship.grid.hp_of(OUTER), 1.0, "the crew leave the outer hull alone")
	ship.grid.hp[INNER] = 1.0
	jobs.build_board(ship)
	check(not jobs.board["block:15,14"].get("hull", false), "an inner wall is no hull job")
	_run(jobs, ship, 40.0)
	check(not ship.grid.hp.has(INNER), "they mend the inner wall")
	eq(ship.grid.hp_of(OUTER), 1.0, "still not the hull")


func test_a_drone_takes_hull_damage_before_a_damaged_inner_wall() -> void:
	var ship := _ship()
	ship.grid.hp[OUTER] = 1.0
	ship.grid.hp[INNER] = 1.0
	var d := CrewMember.new("Drone", Pathfinder.centre_of(Vector2i(14, 12), 1), "drone")
	ship.crew.append(d)
	var jobs := Jobs.new()
	_run(jobs, ship, 1.0)
	eq(str(d.job.get("key", "")), "block:15,8", "the hull first, then what the crew can't reach")


func test_a_destroyed_part_is_not_repaired_by_anyone() -> void:
	var ship := _ship()
	var uid := Fixture.put(ship, "reactor_mk1", 18, 10)
	ship.components.wreck(uid)
	var ada := CrewMember.new("Ada", Pathfinder.centre_of(Vector2i(14, 10)))
	var d := CrewMember.new("Drone", Pathfinder.centre_of(Vector2i(12, 12), 1), "drone")
	ship.crew.append(ada)
	ship.crew.append(d)
	var jobs := Jobs.new()
	jobs.build_board(ship)
	check(not jobs.board.has("fix:%d" % uid), "no repair job for a wreck")
