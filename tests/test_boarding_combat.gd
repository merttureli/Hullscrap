extends "res://tests/base_test.gd"
## Boarding, stage B2 (docs/BOARDING.md, scripts/board/arms.gd, foes.gd, party.gd): the soldier's weapon and its ammo, the foes and how they
## notice, chase, flee and hide, the crew who come along, the downed rules and the Hollow falling while he is aboard.

const Site = preload("res://scripts/board/site.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Foes = preload("res://scripts/board/foes.gd")
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
	s.foes = Foes.new(s)
	s.foes.spawn_site({})
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


# --- the foes ---------------------------------------------------------------------------------------------------

## A visit with no foes and two spots in its biggest room: {s, a (where the soldier stands), b (a foe's spot, 6 to 8 cells off in a clear line), room}.
func _arena(kind := "station", seed_value := 31) -> Dictionary:
	var s = _visit(kind, seed_value)
	s.foes.list.clear()
	var site = s.site
	var best := -1
	var most := 0
	for r in site.rooms:
		if r["purpose"] == "gone" or r["corridor"] or s.foes._red.has(r["id"]):
			continue  # (a room with an emergency light shows him from further)
		var n: int = site.free_anchors(r["id"]).size()
		if n > most:
			most = n
			best = r["id"]
	var anchors: Array = site.free_anchors(best)
	for a in anchors:
		for b in anchors:
			var pa := Vector2(a) + Vector2.ONE
			var pb := Vector2(b) + Vector2.ONE
			var d := pa.distance_to(pb)
			if d >= 6.0 and d <= 8.0 and site.clear_line(pa, pb):
				s.soldier.pos = pa
				return {"s": s, "a": pa, "b": pb, "room": best}
	return {"s": s, "a": Vector2.ZERO, "b": Vector2.ZERO, "room": best}


func _run(s, seconds: float, aim := 0.0, light := true, dt := 0.05) -> void:
	for i in int(seconds / dt):
		s.tick(dt, aim, light)


func test_a_foe_sees_him_in_his_own_beam_from_far_but_not_in_the_dark() -> void:
	var d := _arena()
	check(d["a"] != Vector2.ZERO, "the biggest room has two spots 6 to 8 cells apart")
	var s = d["s"]
	var f: Dictionary = s.foes.add("pirate", d["b"], d["room"])
	f["base"] = (d["a"] - d["b"]).angle()  # it stands looking his way
	f["m"].facing = Vector2.from_angle(f["base"])
	var toward: float = (d["b"] - d["a"]).angle()
	_run(s, 4.0, toward + 2.5, false)
	eq(f["mode"], "idle", "with the light off and the beam elsewhere it does not see him at 6+ cells")
	_run(s, 0.3, toward + 2.5, true)
	eq(f["mode"], "idle", "a beam pointed away does not light it either")
	_run(s, 2.0, toward, true)
	check(f["mode"] in ["hunt", "attack"], "his beam on it from the same spot: it sees him (%s)" % f["mode"])
	var back: Dictionary = _arena()
	var s2 = back["s"]
	var g: Dictionary = s2.foes.add("pirate", back["b"], back["room"])
	g["base"] = (back["a"] - back["b"]).angle() + 3.0  # looking away
	g["m"].facing = Vector2.from_angle(g["base"])
	_run(s2, 0.5, (back["b"] - back["a"]).angle(), true)
	eq(g["mode"], "idle", "a foe looking the other way does not see him")


func test_a_close_foe_sees_him_even_in_the_dark() -> void:
	var d := _arena()
	var s = d["s"]
	var near: Vector2 = d["a"] + (d["b"] - d["a"]).normalized() * 3.0
	var f: Dictionary = s.foes.add("pirate", near, d["room"])
	f["base"] = (d["a"] - near).angle()
	f["m"].facing = Vector2.from_angle(f["base"])
	_run(s, 2.0, (near - d["a"]).angle() + 2.5, false)
	check(f["mode"] in ["hunt", "attack"], "at 3 cells it sees him with no light on (%s)" % f["mode"])


func test_a_shot_alerts_every_foe_within_twelve_cells_and_no_other() -> void:
	var d := _arena()
	var s = d["s"]
	var site = s.site
	var near: Dictionary = s.foes.add("pirate", d["b"], d["room"])
	near["base"] = (d["a"] - d["b"]).angle() + 3.0
	var far_room := -1
	var far_pos := Vector2.ZERO
	for r in site.rooms:
		if r["purpose"] == "gone" or r["id"] == d["room"]:
			continue
		for a in site.free_anchors(r["id"]):
			var p := Vector2(a) + Vector2.ONE
			if p.distance_to(d["a"]) > 14.0 and far_room < 0:
				far_room = r["id"]
				far_pos = p
	check(far_room >= 0, "the station has a room more than 14 cells off")
	var far: Dictionary = s.foes.add("pirate", far_pos, far_room)
	s.soldier.pos = d["a"]
	eq(s.fire(0.0), "shot", "he fires")
	_run(s, 0.1)
	eq(near["mode"], "hunt", "the foe close by comes to look")
	eq(far["mode"], "idle", "the one 14 cells away does not stir")
	check(near["target"].distance_to(d["a"]) < 0.01, "and it heads for where the shot came from")


func test_a_hunter_finds_its_way_to_him_by_the_pathfinder() -> void:
	var s = _visit("station", 31)
	s.foes.list.clear()
	var spots: Array = s.foes._spots(14.0)
	check(not spots.is_empty(), "there is a spot far from the airlock")
	var from: Vector2 = spots[0]["pos"]
	var f: Dictionary = s.foes.add("scavenger", from, spots[0]["room"])
	f["mode"] = "hunt"
	f["target"] = s.soldier.pos
	var start := from.distance_to(s.soldier.pos)
	var closest := start
	var saw_path := false
	for i in 1200:  # up to a minute
		s.tick(0.05, 0.0, false)
		saw_path = saw_path or f["m"].path.size() > 1
		closest = minf(closest, f["m"].pos.distance_to(s.soldier.pos))
		if f["mode"] == "attack":
			break
	check(saw_path, "it walks a path of anchors")
	check(closest < start * 0.7, "and comes much closer (%.1f of %.1f)" % [closest, start])
	check(f["mode"] in ["attack", "hunt"], "in the fight (%s)" % f["mode"])


func test_a_scavenger_runs_when_hurt_and_a_healthy_one_does_not() -> void:
	var d := _arena()
	var s = d["s"]
	var f: Dictionary = s.foes.add("scavenger", d["b"], d["room"])
	var well: Dictionary = s.foes.add("scavenger", d["b"] + Vector2(0.0, 0.0), d["room"])
	f["mode"] = "hunt"
	f["target"] = d["a"]
	well["mode"] = "hunt"
	well["target"] = d["a"]
	f["m"].hp = 8.0
	var start: float = f["m"].pos.distance_to(d["a"])
	_run(s, 8.0, 0.0, true)
	eq(f["mode"], "flee", "at 20% it runs")
	check(f["m"].pos.distance_to(d["a"]) > start + 2.0, "away from him (%.1f then %.1f)" % [start, f["m"].pos.distance_to(d["a"])])
	check(well["mode"] != "flee", "the healthy one stays in the fight")


func test_a_pirate_goes_behind_a_prop_and_shows_less_of_itself_there() -> void:
	var s = _visit("nest", 11)
	s.foes.list.clear()
	var f: Dictionary = {}
	for r in s.site.rooms:
		if r["purpose"] == "gone" or f.size() > 0:
			continue
		var anchors: Array = s.site.free_anchors(r["id"])
		for a in anchors:
			for b in anchors:
				var pa := Vector2(a) + Vector2.ONE
				var pb := Vector2(b) + Vector2.ONE
				if f.is_empty() and pa.distance_to(pb) >= 4.0 and pa.distance_to(pb) <= 9.0:
					var cand: Dictionary = s.foes.add("pirate", pa, r["id"])
					if s.foes._take_cover(cand, {"pos": pb}):
						f = cand
						s.soldier.pos = pb
					else:
						s.foes.list.erase(cand)
	check(not f.is_empty(), "a nest has a room with a prop to stand behind")
	if f.is_empty():
		return
	eq(f["mode"], "cover", "it goes to cover")
	var spot: Vector2 = f["cover_pos"]
	check(s.site.props.any(func(p): return p["blocks"] and s.site.centre_of(p).distance_to(spot) <= 2.4), "beside a prop")
	check(not f["m"].path.is_empty(), "along a path")
	var r_open: float = s.foes.bodies()[0]["r"]
	for i in 400:
		s.tick(0.05, 0.0, false)
		if f["m"].path.is_empty():
			break
	var r_cover: float = s.foes.bodies()[0]["r"] if f["mode"] == "cover" else r_open
	check(r_cover < r_open, "behind it, it is a smaller target (%.2f against %.2f)" % [r_cover, r_open])


func test_a_hollow_touched_walks_slowly_strikes_and_says_something_polite() -> void:
	var d := _arena()
	var s = d["s"]
	var f: Dictionary = s.foes.add("hollow_touched", d["b"], d["room"])
	f["base"] = (d["a"] - d["b"]).angle()
	f["m"].facing = Vector2.from_angle(f["base"])
	_run(s, 3.0, (d["b"] - d["a"]).angle(), true)
	check(f["mode"] in ["hunt", "attack"], "it notices him")
	var said: Array = s.take_events().filter(func(e): return e["type"] == "line")
	eq(said.size(), 1, "and says one line")
	check(str(said[0]["text"]) != "", "a polite one: %s" % str(said[0]["text"]))
	var hp: float = s.soldier.hp
	_run(s, 12.0, (d["b"] - d["a"]).angle(), true)
	check(s.soldier.hp < hp, "it reaches him and strikes")
	check(f["m"].speed < s.soldier.speed * 0.7, "but it walks slower than he does")


func test_the_crawler_moves_only_while_no_light_is_on_it_and_lunges() -> void:
	var d := _arena()
	var s = d["s"]
	var site = s.site
	var f: Dictionary = s.foes.add("crawler", d["b"], d["room"])
	f["hidden"] = false
	f["mode"] = "stalk"
	var toward: float = (d["b"] - d["a"]).angle()
	var start: Vector2 = f["m"].pos
	_run(s, 3.0, toward, true)
	check(f["m"].pos.distance_to(start) < 0.01, "in his beam it does not move")
	check(f["frozen"], "it is frozen")
	check(s.contacts().all(func(c): return not c["moving"]) and not s.contacts().is_empty(), "and the tracker has it, standing still")
	_run(s, 0.4, toward + 2.6, true)
	check(f["m"].pos.distance_to(start) > 1.0, "look away and it comes (%.1f cells)" % f["m"].pos.distance_to(start))
	check(f["m"].pos.distance_to(s.soldier.pos) < start.distance_to(s.soldier.pos), "toward him")
	var hp: float = s.soldier.hp
	_run(s, 3.0, toward + 2.6, false)
	check(s.soldier.hp < hp, "unseen, it lunges and bites")
	check(f["lunge_cd"] > 0.0 or f["mode"] == "retreat", "and then it breaks off")
	# in a vent it is hidden: nothing on the tracker, nothing to hit
	var g: Dictionary = s.foes.add("crawler", d["b"], d["room"])
	check(g["hidden"] and g["mode"] == "hidden", "a new crawler is in its vent")
	var hidden_ok := true
	for c in s.contacts():
		hidden_ok = hidden_ok and c["pos"] != g["m"].pos
	check(hidden_ok, "and not on the tracker")
	check(s.foes.bodies().all(func(b): return b["ref"] != g), "nor to be shot")
	check(not site.rooms.is_empty(), "(a site)")


func test_the_crawler_comes_out_of_a_vent_when_he_is_near_and_goes_back() -> void:
	var s = _visit("station", 31)
	s.foes.list.clear()
	check(s.foes.vents.size() >= 3 and s.foes.vents.size() <= 5, "a site has 3 to 5 vents (%d)" % s.foes.vents.size())
	var f: Dictionary = s.foes.add("crawler", s.foes.vents[0], 0)
	f["wait"] = 0.0
	var v: Vector2 = s.foes.vents[0]
	# stand 8 to 14 cells from some vent, in the dark
	var spot := Vector2.ZERO
	for r in s.site.rooms:
		for a in s.site.free_anchors(r["id"]):
			var p := Vector2(a) + Vector2.ONE
			if spot == Vector2.ZERO and p.distance_to(v) >= 8.0 and p.distance_to(v) <= 14.0 and s.foes.vents.all(func(w): return w.distance_to(p) > 3.5):
				spot = p
	s.soldier.pos = spot
	var came := false
	for i in 400:
		s.tick(0.05, 0.0, false)
		came = came or not f["hidden"]
	check(came, "it came out to stalk")
	check(s.take_events().any(func(e): return e["type"] == "emerge"), "and the view was told")


func test_a_hacked_sentry_switches_sides() -> void:
	var d := _arena()
	var s = d["s"]
	var site = s.site
	var sentry: Dictionary = s.foes.add("sentry", d["b"], d["room"])
	var facing: float = (d["a"] - d["b"]).angle()
	sentry["aim"] = facing
	sentry["base"] = facing
	# in front of it he cannot hack; behind it he can
	var front: Vector2 = d["b"] + Vector2.from_angle(facing) * 1.5
	var back: Vector2 = d["b"] - Vector2.from_angle(facing) * 1.5
	check(not s.foes.can_hack(sentry, front), "not from the front")
	check(s.foes.can_hack(sentry, back) or not site.clear_line(d["b"], back), "from behind (when the cell is on the floor)")
	s.foes.hack(sentry)
	eq(sentry["team"], "player", "it is his")
	check(s.foes.bodies().all(func(b): return b["ref"] != sentry), "his shots pass it")
	check(s.foes.contacts().is_empty(), "and the tracker does not show it")
	# a pirate in its sights is shot at, and he is not
	s.soldier.pos = d["b"] - Vector2.from_angle(facing) * 2.0
	var foe: Dictionary = s.foes.add("pirate", d["a"], d["room"])
	foe["base"] = foe["base"] + 3.0
	var hp: float = foe["m"].hp
	var mine: float = s.soldier.hp
	_run(s, 3.0, 0.0, false)
	check(foe["m"].hp < hp or foe["mode"] != "idle", "the sentry fires on the foe or the foe answers")
	check(s.soldier.hp >= mine - 60.0, "(he is not its target)")


func test_an_unhacked_sentry_sweeps_then_tracks_and_shoots_him() -> void:
	var d := _arena()
	var s = d["s"]
	var sentry: Dictionary = s.foes.add("sentry", d["b"], d["room"])
	var toward: float = (d["a"] - d["b"]).angle()
	sentry["aim"] = toward
	sentry["base"] = toward
	var hp: float = s.soldier.hp
	_run(s, 4.0, (d["b"] - d["a"]).angle(), true)
	check(s.soldier.hp < hp, "a sentry that sees him in its cone fires")
	check(s.take_events().any(func(e): return e["type"] == "whir"), "with a whir")
	check(s.contacts().all(func(c): return not c["moving"]), "it never moves, so the tracker does not ping it")


# --- spawning ---------------------------------------------------------------------------------------------------

func _spawned(kind: String, seed_value: int, ctx := {}) -> Array:
	var s = _visit(kind, seed_value)
	s.foes.spawn_site(ctx)
	return s.foes.list.filter(func(f): return f["kind"] != "crawler")


func test_the_number_of_foes_follows_the_kind_of_site() -> void:
	var want := {"derelict": [0, 2], "station": [3, 7], "nest": [5, 8]}
	for kind in want:
		var total := 0.0
		for sd in 24:
			var n := _spawned(kind, sd * 5 + 1).size()
			check(n >= want[kind][0] and n <= want[kind][1], "%s %d: %d foes is %s" % [kind, sd, n, str(want[kind])])
			total += n
		var mean := total / 24.0
		check(mean >= want[kind][0] + 0.3 and mean <= want[kind][1] - 0.3, "%s: %.1f on average, inside the range" % [kind, mean])
	eq(_spawned("wreck", 3, {"crew": 3}).size(), 3, "a wreck holds its surviving crew")
	eq(_spawned("wreck", 3, {"crew": 9}).size(), 4, "up to four")
	eq(_spawned("wreck", 3, {}).size(), 0, "none, when nobody lived")


func test_foes_stand_in_rooms_away_from_the_airlock_and_the_mix_follows_the_kind() -> void:
	var kinds := {}
	for sd in 20:
		var s = _visit("station", sd * 3 + 2)
		for f in s.foes.list:
			kinds[f["kind"]] = int(kinds.get(f["kind"], 0)) + 1
			check(f["m"].pos.distance_to(s.site.airlock["spawn"]) >= 8.9 or f["kind"] == "crawler", "a foe stands at least 9 cells from where he arrives")
			check(s.site.room_at(f["m"].pos) >= 0, "and in a room")
			check(f["kind"] in ["scavenger", "pirate", "sentry", "crawler"], "a station is not Hollow: %s" % f["kind"])
	check(int(kinds.get("scavenger", 0)) > int(kinds.get("pirate", 0)), "scavengers are the commonest on a station")
	check(kinds.has("sentry"), "and there are sentries")
	var hollow := _spawned("station", 5, {"hollow": true})
	check(hollow.any(func(f): return f["kind"] == "hollow_touched"), "the Hollow's place is held by hollow_touched")


func test_about_one_site_in_six_has_a_crawler() -> void:
	var n := 0
	for sd in 120:
		var s = _visit("derelict", sd * 7 + 3)
		if s.foes.list.any(func(f): return f["kind"] == "crawler"):
			n += 1
	check(n >= 8 and n <= 36, "%d crawler sites of 120 is about one in six" % n)


func test_the_same_site_gives_the_same_foes_and_the_same_fight() -> void:
	var digests := []
	for k in 2:
		var s = _visit("station", 31)
		var bits := []
		for f in s.foes.list:
			bits.append([f["kind"], f["m"].pos, f["id"]])
		s.soldier.pos = s.foes.list[0]["m"].pos + Vector2(3.0, 0.0) if not s.foes.list.is_empty() else s.soldier.pos
		for i in 400:
			s.fire(0.5)
			s.tick(0.05, 0.5, true)
		for f in s.foes.list:
			bits.append([f["mode"], f["m"].hp, f["m"].pos])
		bits.append([s.soldier.hp, s.soldier.pos, s.rng.randi()])
		digests.append(var_to_str(bits))
	eq(digests[0], digests[1], "two runs of the same fight agree to the last number")
	var other = _visit("station", 32)
	check(var_to_str(other.foes.list.map(func(f): return f["m"].pos)) != var_to_str(_visit("station", 31).foes.list.map(func(f): return f["m"].pos)), "another site has other foes")


func test_beaten_foes_stay_beaten_on_the_next_visit() -> void:
	var s = _visit("station", 31)
	check(s.foes.list.size() >= 3, "foes to beat")
	var first: Dictionary = s.foes.list[0]
	s.foes.hurt(first, 9999.0, first["m"].pos)
	var mem: Dictionary = s.foes.memory()
	eq(mem["dead"], [first["id"]], "the memory names the fallen")
	var again = _visit("station", 31)
	again.foes.spawn_site({"mem": mem})
	check(again.foes.find(first["id"])["dead"], "he is still down on the next visit")
	eq(again.foes.live().size(), s.foes.live().size(), "and the rest are as they were")
