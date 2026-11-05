extends "res://tests/base_test.gd"
## The healing arm (docs/DRONES.md section 10, scripts/crew/jobs.gd): Medbay Mk2 and Mk3 reach crew within stats.reach cells of walking
## (floor and doors, not walls) and heal one patient at a time where they stand.

const Fixture = preload("res://tests/fixture_ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Ship = preload("res://scripts/ship/ship.gd")


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, want, got])


func _npc(p_name: String, x: int, y: int) -> CrewMember:
	return CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)))


func _player(x: int, y: int) -> CrewMember:
	var m := _npc("Soldier", x, y)
	m.is_player = true
	return m


## The room ship with an arm `id` at (10, 10) (cells x 10..11, y 10..11), and a reactor on a cable when `power`.
func _arm_ship(id := "medbay_mk2", power := true) -> Dictionary:
	var ship := Fixture.room_ship()
	var d := {"ship": ship}
	d["arm"] = Fixture.put(ship, id, 10, 10)
	if power:
		Fixture.put(ship, "reactor_mk1", 17, 12)
		Fixture.wire(ship, [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11), Vector2i(16, 11), Vector2i(16, 12), Vector2i(17, 12)])
	ship.refresh()
	return d


func _hurt(m: CrewMember, hp: float) -> CrewMember:
	m.hp = hp
	return m


func test_the_arms_are_2x2_with_the_owners_numbers() -> void:
	var ship := Ship.new_starter()
	var a: Dictionary = ship.components.def("medbay_mk2")
	var b: Dictionary = ship.components.def("medbay_mk3")
	eq(a["size"], [2, 2], "Mk2 is 2x2")
	eq(b["size"], [2, 2], "Mk3 is 2x2")
	eq([a["power"], b["power"]], [-3, -4], "power")
	eq([a["stats"]["heal"], b["stats"]["heal"]], [1.2, 1.6], "heal rate")
	eq([int(a["stats"]["reach"]), int(b["stats"]["reach"])], [6, 9], "reach")
	check(Jobs.is_arm(a) and Jobs.is_arm(b) and not Jobs.is_arm(ship.components.def("medbay")), "Mk1 stays the bed")


func test_an_arm_heals_a_crew_member_across_the_room_at_the_medbay_rate_times_its_own() -> void:
	var d := _arm_ship()
	var ship: Ship = d["ship"]
	var m := _hurt(_npc("Ada", 13, 10), 50.0)  # four cells of floor from the arm
	ship.crew.append(m)
	var jobs := Jobs.new()
	jobs.tick(ship, 1.0)
	near(m.hp, 50.0 + 15.0 * 1.2, "Mk2: 1.2 x 15 a second where they stand")
	eq(jobs.arm_patients.get(d["arm"], ""), "Ada", "the arm's patient")


func test_the_reach_is_a_walk_through_floor_so_distance_and_walls_count() -> void:
	var d := _arm_ship()
	var ship: Ship = d["ship"]
	var jobs := Jobs.new()
	var cells: Dictionary = jobs.arm_cells(ship, d["arm"])
	check(cells.has(Vector2i(17, 10)), "six steps from the arm's edge: in reach")
	check(not cells.has(Vector2i(18, 10)), "seven steps: out of reach")
	var far := _hurt(_npc("Far", 18, 14), 50.0)
	ship.crew.append(far)
	jobs.tick(ship, 1.0)
	near(far.hp, 50.0, "out of reach, not healed")
	# a wall between them: the cell is close but the walk is not
	var d3 := _arm_ship("medbay_mk3")
	var s3: Ship = d3["ship"]
	for y in range(9, 17):
		s3.grid.force_tile(Vector2i(13, y), "wall")
	s3.refresh()
	var j3 := Jobs.new()
	check(not j3.arm_cells(s3, d3["arm"]).has(Vector2i(14, 12)), "a wall blocks the reach")
	var d4 := _arm_ship("medbay_mk3")
	check(Jobs.new().arm_cells(d4["ship"], d4["arm"]).has(Vector2i(20, 10)), "Mk3 reaches nine cells")


func test_a_door_does_not_block_the_reach() -> void:
	var d := _arm_ship()
	var ship: Ship = d["ship"]
	for y in range(9, 17):
		ship.grid.force_tile(Vector2i(13, y), "wall")
	ship.grid.force_tile(Vector2i(13, 12), "door")
	ship.grid.force_tile(Vector2i(13, 13), "door")
	ship.refresh()
	var cells: Dictionary = Jobs.new().arm_cells(ship, d["arm"])
	check(cells.has(Vector2i(15, 12)), "through the door")


func test_the_soldier_first_at_equal_hp_then_the_lowest_share() -> void:
	var d := _arm_ship()
	var ship: Ship = d["ship"]
	var ada := _hurt(_npc("Ada", 13, 10), 50.0)
	var sol := _hurt(_player(13, 12), 50.0)
	ship.crew.append_array([ada, sol])
	var jobs := Jobs.new()
	jobs.tick(ship, 0.1)
	eq(jobs.arm_patients.get(d["arm"], ""), "Soldier", "equal hp: the soldier")
	# fresh arm state: a lower share beats the soldier
	var d2 := _arm_ship()
	var s2: Ship = d2["ship"]
	var ada2 := _hurt(_npc("Ada", 13, 10), 20.0)
	var sol2 := _hurt(_player(13, 12), 50.0)
	s2.crew.append_array([sol2, ada2])
	var j2 := Jobs.new()
	j2.tick(s2, 0.1)
	eq(j2.arm_patients.get(d2["arm"], ""), "Ada", "the lowest share first")


func test_a_tie_goes_to_whoever_mans_a_station() -> void:
	var d := _arm_ship()
	var ship: Ship = d["ship"]
	var a := _hurt(_npc("Ada", 13, 10), 50.0)
	var b := _hurt(_npc("Bo", 13, 12), 50.0)
	ship.crew.append_array([a, b])
	b.job = {"key": "man:1", "type": "man_station", "uid": 1, "priority": 50, "label": "x"}
	var jobs := Jobs.new()
	jobs._choose_arm_patients(ship, 0.1)
	eq(jobs.arm_patients.get(d["arm"], ""), "Bo", "a crew member at a station comes before the one who is not")


func test_one_patient_at_a_time_and_no_flicker() -> void:
	var d := _arm_ship()
	var ship: Ship = d["ship"]
	var ada := _hurt(_npc("Ada", 13, 10), 60.0)
	var bo := _hurt(_npc("Bo", 13, 12), 80.0)
	ship.crew.append_array([ada, bo])
	var jobs := Jobs.new()
	jobs.tick(ship, 0.1)
	eq(jobs.arm_patients.get(d["arm"], ""), "Ada", "the lowest share first")
	near(bo.hp, 80.0, "one patient: the other is not healed")
	bo.hp = 5.0  # Bo is now worse off, but Ada stays the patient until she is full
	for i in 10:
		jobs.tick(ship, 0.1)
		eq(jobs.arm_patients.get(d["arm"], ""), "Ada", "no flicker")
	near(bo.hp, 5.0, "Bo waits")
	jobs.tick(ship, 10.0)
	near(ada.hp, 100.0, "Ada is full")
	jobs.tick(ship, 0.1)
	eq(jobs.arm_patients.get(d["arm"], ""), "Bo", "then the arm takes Bo")
	# a patient who leaves the reach is dropped for the next
	var ada2 := _hurt(_npc("Ada", 13, 10), 60.0)
	var bo2 := _hurt(_npc("Bo", 13, 12), 80.0)
	var d2 := _arm_ship()
	var s2: Ship = d2["ship"]
	s2.crew.append_array([ada2, bo2])
	var j2 := Jobs.new()
	j2.tick(s2, 0.1)
	ada2.pos = Pathfinder.centre_of(Vector2i(20, 14))
	for i in 6:
		j2.tick(s2, 0.1)
	eq(j2.arm_patients.get(d2["arm"], ""), "Bo", "out of reach: the arm turns to the next")


func test_no_healing_without_air_for_those_who_breathe() -> void:
	var d := _arm_ship()
	var ship: Ship = d["ship"]
	var m := _hurt(_npc("Ada", 13, 10), 50.0)
	var s := _hurt(_npc("Suit", 13, 12), 50.0)
	s.equip("suit")
	ship.crew.append_array([m, s])
	var room: int = ship.atmosphere.room_at(m.cell())
	ship.atmosphere.pressure[room] = 0.0
	var jobs := Jobs.new()
	jobs._choose_arm_patients(ship, 0.1)
	eq(jobs.arm_patients.get(d["arm"], ""), "Suit", "the one who needs no air is the only patient")
	var d2 := _arm_ship()
	var s2: Ship = d2["ship"]
	var m2 := _hurt(_npc("Ada", 13, 10), 50.0)
	s2.crew.append(m2)
	s2.atmosphere.pressure[s2.atmosphere.room_at(m2.cell())] = 0.0
	var j2 := Jobs.new()
	j2._choose_arm_patients(s2, 0.1)
	check(j2.arm_patients.is_empty(), "no air, no patient")
	near(float(j2.arm_heal.get("Ada", 0.0)), 0.0, "and no heal")


func test_an_arm_out_of_power_heals_nobody() -> void:
	var d := _arm_ship("medbay_mk2", false)
	var ship: Ship = d["ship"]
	var m := _hurt(_npc("Ada", 13, 10), 50.0)
	ship.crew.append(m)
	var jobs := Jobs.new()
	jobs.tick(ship, 2.0)
	near(m.hp, 50.0, "no power, no healing")
	check(jobs.arm_patients.is_empty(), "and no patient")


func test_crew_in_reach_keep_working_and_do_not_walk_to_a_bed() -> void:
	var d := _arm_ship()
	var ship: Ship = d["ship"]
	Fixture.put(ship, "bed", 20, 10)  # a bed far away
	var m := _hurt(_npc("Ada", 13, 10), 50.0)
	ship.crew.append(m)
	var jobs := Jobs.new()
	for i in 30:
		jobs.tick(ship, 0.1)
	check(m.job.is_empty() or m.job["type"] != "rest", "an idle, hurt crew member in reach does not go to rest")
	check(m.cell().x < 17, "they did not walk off to the bed")
	# the same crew member out of the arm's reach does go to bed
	var d2 := _arm_ship("medbay_mk2", false)
	var s2: Ship = d2["ship"]
	Fixture.put(s2, "bed", 20, 10)
	var m2 := _hurt(_npc("Ada", 13, 10), 50.0)
	s2.crew.append(m2)
	var j2 := Jobs.new()
	j2.tick(s2, 1.1)
	check(not m2.job.is_empty() and m2.job["type"] == "rest", "with the arm unpowered they go to the bed")


func test_mk1_stays_a_bed_and_the_arm_is_not_one() -> void:
	var ship := Fixture.room_ship()
	var arm := Fixture.put(ship, "medbay_mk2", 10, 10)
	Fixture.put(ship, "reactor_mk1", 17, 12)
	Fixture.wire(ship, [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11), Vector2i(16, 11), Vector2i(16, 12), Vector2i(17, 12)])
	ship.refresh()
	var m := _hurt(_npc("Ada", 10, 10), 50.0)  # lying on the arm's base
	ship.crew.append(m)
	var jobs := Jobs.new()
	jobs.tick(ship, 1.0)
	near(m.hp, 50.0 + 18.0, "lying on the base heals by the arm only once (no bed rate on top)")
	check(arm >= 0, "placed")
