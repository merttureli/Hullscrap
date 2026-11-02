extends "res://tests/base_test.gd"
## Boarding, stage B2 (docs/BOARDING.md, scripts/board/arms.gd, foes.gd, party.gd): the soldier's weapon and its ammo, the foes and how they
## notice, chase, flee and hide, the crew who come along, the downed rules and the Hollow falling while he is aboard.

const Site = preload("res://scripts/board/site.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _ship(rounds := 40) -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.inventory.add("hand_ammo", rounds)
	return s


## A visit to a site of `kind` with no sector or campaign behind it.
func _visit(kind := "station", seed_value := 31, ship = null):
	var sh = ship if ship != null else _ship()
	var s = Boarding.start(null, null, "p%d" % seed_value, {"kind": kind}, sh)
	s.site = Site.make(seed_value, kind, {"faction": "clans"})
	s.soldier.pos = s.site.airlock["spawn"]
	return s


# --- the soldier's weapon -----------------------------------------------------------------------------------------

func test_a_ray_hits_the_first_body_and_a_wall_stops_it() -> void:
	var s = _visit()
	var rng := RandomNumberGenerator.new()
	var from: Vector2 = s.soldier.pos
	var out: float = (-s.site.airlock["normal"] as Vector2).angle()  # into the hull
	var free := -1.0
	for k in 16:  # a direction with five clear cells
		var a := TAU * k / 16.0
		if s.site.clear_line(from, from + Vector2.from_angle(a) * 5.0) and s.site.cover_between(from, from + Vector2.from_angle(a) * 5.0) == 0:
			free = a
			break
	check(free >= 0.0, "the airlock has an open line")
	var near := {"pos": from + Vector2.from_angle(free) * 3.0, "r": 0.75, "ref": "near"}
	var far := {"pos": from + Vector2.from_angle(free) * 4.5, "r": 0.75, "ref": "far"}
	var r := Arms.trace(s.site, from, free, 8.0, [far, near], rng)
	eq(r["ref"], "near", "the nearer body takes the shot")
	eq(r["kind"], "body", "and it stopped there")
	var wall := Arms.trace(s.site, from, s.site.airlock["normal"].angle(), 30.0, [], rng)
	check(wall["kind"] == "wall" and wall["end"].distance_to(from) < 10.0, "a shot out through the hull stops at the wall")
	check(out == out, "(angles are numbers)")


func test_a_shut_door_stops_a_shot_and_an_open_one_does_not() -> void:
	var s = _visit("station", 7)
	var site = s.site
	var rng := RandomNumberGenerator.new()
	var found := false
	for d in site.doors:
		if d["lock"] == "gone":
			continue
		var a: Vector2i = d["cells"][0]
		var b: Vector2i = d["cells"][1]
		var along := Vector2(b - a).normalized()  # the door runs this way: the line through it is across
		var across := along.orthogonal()
		var mid: Vector2 = site.door_centre(d)
		var p0 := mid - across * 2.0
		var p1 := mid + across * 2.0
		if site.opaque(Vector2i(floori(p0.x), floori(p0.y))) or site.opaque(Vector2i(floori(p1.x), floori(p1.y))):
			continue
		found = true
		site.grid.set_door_open(a, false)
		check(not site.clear_line(p0, p1), "a shut door blocks the line")
		var shut := Arms.trace(site, p0, across.angle(), 4.0, [{"pos": p1, "r": 0.75, "ref": "x"}], rng)
		eq(shut["kind"], "wall", "and the shot")
		site.grid.set_door_open(a, true)
		check(site.clear_line(p0, p1), "an open door lets the line through")
		var open := Arms.trace(site, p0, across.angle(), 4.0, [{"pos": p1, "r": 0.75, "ref": "x"}], rng)
		eq(open["ref"], "x", "and the shot")
		break
	check(found, "the station has a door to test")


func test_the_magazine_the_reload_and_the_reserve_count() -> void:
	var sh := _ship(40)
	var s = _visit("station", 31, sh)
	var g: Dictionary = s.gun()
	eq(g["id"], "service_pistol", "a human carries the service pistol")
	eq(g["mag"], 8, "a pistol holds 8")
	eq(s.reserve(), 32, "the rest stays in the hold")
	for i in 8:
		eq(s.fire(0.0), "shot", "shot %d" % i)
		s.tick(0.7)
	eq(g["mag"], 0, "the magazine is empty")
	eq(s.fire(0.0), "empty", "and it clicks")
	check(s.take_events().any(func(e): return e["type"] == "click"), "the click is told")
	check(s.reload(), "R reloads")
	eq(s.fire(0.0), "reloading", "he cannot shoot meanwhile")
	s.tick(1.0)
	eq(g["mag"], 0, "1.0 s is not enough")
	s.tick(0.3)
	eq(g["mag"], 8, "the magazine is full again")
	eq(s.reserve(), 24, "from the reserve")
	check(not s.reload(), "a full magazine is not reloaded")
	s.fire(0.0)
	s.tick(0.7)
	sh.inventory.add("hand_ammo", -sh.inventory.count("hand_ammo"))
	check(not s.reload(), "no rounds in the hold, no reload")
	s.leave()
	eq(sh.inventory.count("hand_ammo"), 7, "what is loaded goes back to the hold on leaving")


func test_a_found_rifle_is_the_second_weapon_and_q_swaps() -> void:
	var sh := _ship(60)
	sh.inventory.add("rifle", 1)
	var s = _visit("station", 31, sh)
	eq(s.guns.size(), 2, "he carries two")
	eq(s.guns[1]["id"], "carbine", "the rifle is the carbine")
	eq(s.guns[1]["mag"], 20, "a rifle holds 20")
	eq(s.reserve(), 60 - 8 - 20, "both are loaded from the hold")
	check(s.swap(), "Q swaps")
	eq(s.gun()["id"], "carbine", "the rifle is in his hands")
	eq(s.fire(0.0), "wait", "and he cannot fire for a moment")
	s.tick(0.5)
	eq(s.fire(0.0), "shot", "then he can")
	var one = _visit("station", 31, _ship())
	check(not one.swap(), "with one weapon Q does nothing")


func test_picking_up_a_weapon_arms_the_empty_hand() -> void:
	var s = _visit("station", 31, _ship())
	eq(s.guns.size(), 1, "just the sidearm")
	s.ship.inventory.add("rifle", 1)
	var line: String = s._found("rifle")
	check(line.contains("Carbine"), "he says what he took up: %s" % line)
	eq(s.guns.size(), 2, "and carries it")
	eq(s._found("rifle"), "", "a second rifle changes nothing")
	eq(s._found("scrap"), "", "nor does scrap")
