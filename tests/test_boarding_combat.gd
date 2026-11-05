extends "res://tests/base_test.gd"
## Boarding, stage B2 (docs/BOARDING.md, scripts/board/arms.gd, foes.gd, party.gd): the soldier's weapon and its ammo, the foes and how they
## notice, chase, flee and hide, the crew who come along, the downed rules and the Hollow falling while he is aboard.

const Site = preload("res://scripts/board/site.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Party = preload("res://scripts/board/party.gd")
const BoardView = preload("res://scripts/board/board_view.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _ship(rounds := 40) -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.crew.append(CrewMember.new("Rook", Vector2(10, 10), "human"))
	s.crew.append(CrewMember.new("Tess", Vector2(12, 10), "fenn"))
	s.inventory.add("hand_ammo", rounds - s.inventory.count("hand_ammo"))  # (a starter comes with some)
	return s


## A visit to a site of `kind` with no sector or campaign behind it.
func _visit(kind := "station", seed_value := 31, ship = null):
	var sh = ship if ship != null else _ship()
	var s = Boarding.start(null, null, "p%d" % seed_value, {"kind": kind}, sh)
	s.site = Site.make(seed_value, kind, {"faction": "clans", "gen": "classic"})  # (the fights are staged on the classic bands; module stations: test_stations.gd)
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


# --- the crew who come along ------------------------------------------------------------------------------------

func _with_party(count := 2, seed_value := 31):
	var sh := _ship()
	var s = _visit("station", seed_value, sh)
	s.foes.list.clear()
	var names: Array = Party.eligible(sh).map(func(m): return m.name)
	s.join_party(names.slice(0, count))
	return s


func test_any_crew_can_come_posted_or_not_and_no_more_than_two() -> void:
	var sh := _ship()
	var ok: Array = Party.eligible(sh)
	check(ok.size() >= 2, "the rustbucket has crew to take (%d)" % ok.size())
	check(ok.all(func(m): return not m.is_player and not m.is_drone() and not m.is_down()), "none of them is the soldier, the drone or down")
	ok[0].post = 3
	check(Party.eligible(sh).has(ok[0]), "a posted crew member may come too (playtest 2026-11-05)")
	eq(ok[0].post, 3, "and keeps the post to go back to")
	sh.crew.append(CrewMember.new("Vik", Vector2(14, 10), "human"))
	sh.crew.append(CrewMember.new("Ona", Vector2(16, 10), "human"))
	var s = _visit("station", 31, sh)
	eq(s.join_party(sh.crew.map(func(m): return m.name)), 2, "four names, two come")
	for p in s.party:
		check(p["m"] != p["src"], "a copy walks the site")
		check(p["m"].pos.distance_to(s.site.airlock["spawn"]) < 6.0, "by the airlock")


func test_followers_follow_the_soldier_and_stop_near() -> void:
	var s = _with_party()
	var spots: Array = s.foes._spots(14.0)
	s.soldier.pos = spots[0]["pos"]
	var far: float = s.party[0]["m"].pos.distance_to(s.soldier.pos)
	check(far > 10.0, "he is a good way off (%.1f)" % far)
	_run(s, 40.0, 0.0, false)
	for p in s.party:
		var d: float = p["m"].pos.distance_to(s.soldier.pos)
		check(d <= 7.0, "%s caught up (%.1f cells)" % [p["m"].name, d])
	s.soldier.pos += Vector2(1.0, 0.0)
	var before: Array = s.party.map(func(p): return p["m"].pos)
	_run(s, 2.0, 0.0, false)
	check(s.party[0]["m"].pos.distance_to(before[0]) < 2.5, "and they do not crowd him")


func test_followers_shoot_what_is_in_front_of_them() -> void:
	var d := _arena()
	var s = d["s"]
	var sh := _ship()
	s.ship = sh
	s.join_party(Party.eligible(sh).map(func(m): return m.name).slice(0, 1))
	var p: Dictionary = s.party[0]
	p["m"].pos = d["a"]
	s.soldier.pos = d["a"] + Vector2(1.0, 0.0)
	var f: Dictionary = s.foes.add("pirate", d["b"], d["room"])
	f["base"] = (d["a"] - d["b"]).angle() + 3.0
	var hp: float = f["m"].hp
	_run(s, 5.0, 0.0, false)
	check(f["m"].hp < hp or f["dead"], "the follower hit it (%.0f of %.0f)" % [f["m"].hp, hp])
	check(f["mode"] != "idle", "and the shots woke it")


func test_a_downed_follower_is_revived_by_a_mate_in_four_seconds_or_the_soldier() -> void:
	var s = _with_party()
	var a: Dictionary = s.party[0]
	var b: Dictionary = s.party[1]
	a["m"].hp = 0.0
	b["m"].pos = a["m"].pos + Vector2(1.0, 0.0)
	s.soldier.pos = a["m"].pos + Vector2(2.0, 0.0)
	_run(s, 3.0, 0.0, false)
	check(a["m"].is_down(), "three seconds are not enough")
	_run(s, 2.0, 0.0, false)
	check(not a["m"].is_down(), "four seconds are")
	check(a["m"].hp > 0.0 and a["m"].hp < a["m"].max_hp, "and they get up hurt (%.0f of %.0f)" % [a["m"].hp, a["m"].max_hp])
	b["m"].hp = 0.0
	s.revive_member(b["m"])
	check(not b["m"].is_down(), "the soldier's hold ends in revive_member")


func test_a_follower_left_down_is_lost_and_the_ones_standing_go_home() -> void:
	var s = _with_party()
	var sh = s.ship
	var down: Dictionary = s.party[0]
	var up: Dictionary = s.party[1]
	var down_name: String = down["src"].name
	down["m"].hp = 0.0
	up["m"].hp = 30.0
	eq(s.downed_party(), [down_name], "the party knows who is down")
	var res: Dictionary = s.leave()
	eq(res["lost"], [down_name], "the one down is lost")
	check(not sh.crew.has(down["src"]), "off the ship's crew")
	check(sh.dead_crew.has(down_name), "and counted dead")
	check(sh.crew.has(up["src"]) and absf(up["src"].hp - 30.0) < 0.1, "the other is home with the health he had (%.0f)" % up["src"].hp)
	check(s.said.any(func(l): return str(l).contains(down_name)), "and the visit says so")


func test_a_revived_follower_is_not_lost() -> void:
	var s = _with_party()
	var a: Dictionary = s.party[0]
	a["m"].hp = 0.0
	s.revive_member(a["m"])
	var res: Dictionary = s.leave()
	eq(res["lost"], [], "nobody is lost")
	check(s.ship.crew.has(a["src"]), "he is home")


func test_the_soldier_down_wakes_at_the_airlock_hurt_and_the_site_is_closed() -> void:
	var s = _with_party()
	var sh = s.ship
	var down: Dictionary = s.party[0]
	down["m"].hp = 0.0
	s.hurt_member(s.soldier, 999.0, Vector2.ZERO)
	s.tick(0.05, 0.0, true)
	check(s.downed, "he is noticed to be down")
	check(s.take_events().any(func(e): return e["type"] == "downed"), "the view is told")
	var said: int = s.said.size()
	var res: Dictionary = s.leave()
	check(res["downed"] and res["cleared"], "the site is closed for good")
	eq(res["text"], "You come to at the airlock.", "and he says where he is")
	var me = null
	for m in sh.crew:
		if m.is_player:
			me = m
	check(me != null and absf(me.hp - me.max_hp * 0.15) < 0.01, "he is back at 15%% (%.1f of %.0f)" % [me.hp, me.max_hp])
	eq(res["lost"].size(), 1, "the follower who was down is lost")
	check(sh.crew.has(s.party[1]["src"]), "the one standing came back")
	check(said >= 0, "(told)")


func test_a_downed_visit_is_remembered_as_cleared() -> void:
	var camp := Campaign.new(5)
	var sector = camp.current_sector()
	var sh := _ship()
	var s = Boarding.start(camp, sector, "pz", {"kind": "station"}, sh)
	s.hurt_member(s.soldier, 999.0, Vector2.ZERO)
	s.tick(0.05, 0.0, true)
	s.leave()
	check(sector.boarded["pz"]["cleared"], "the sector remembers it closed")


# --- the Hollow falls while he is aboard --------------------------------------------------------------------------

func test_the_hollow_arriving_puts_hollow_touched_on_the_airlock_side_once() -> void:
	var s = _visit("station", 31)
	s.foes.list.clear()
	check(not s.note_hollow(false), "nothing while the place holds")
	check(s.note_hollow(true), "the tide takes it")
	check(not s.note_hollow(true), "and only once")
	var made: Array = s.foes.list.filter(func(f): return f["kind"] == "hollow_touched")
	check(made.size() >= 2 and made.size() <= 3, "two or three come (%d)" % made.size())
	for f in made:
		check(f["m"].pos.distance_to(s.soldier.pos) >= 4.5, "not on top of him")
		eq(f["mode"], "hunt", "already coming")
	var avg := 0.0
	for f in made:
		avg += f["m"].pos.distance_to(s.site.airlock["spawn"]) / made.size()
	check(avg < 14.0, "on the airlock side (%.1f cells from it)" % avg)
	check(s.take_events().any(func(e): return e["type"] == "hollow"), "the view is told")
	var born = _visit("station", 31)
	born.hollow_place = true
	check(not born.note_hollow(true), "a place that was the Hollow's already has its own")


# --- the view ---------------------------------------------------------------------------------------------------

## A boarding view with no scene round it, aboard `s`.
func _view(s, ask := false):
	var b := BoardView.new()
	b.ask_party = ask
	b.enter(s)
	return b


func _step(b, seconds: float, dt := 0.05) -> void:
	for i in int(seconds / dt):
		if not b.active:
			return
		b.step(dt)


func test_the_crew_picker_takes_at_most_two_and_the_world_waits_while_it_is_up() -> void:
	var sh := _ship()
	sh.crew.append(CrewMember.new("Vik", Vector2(14, 10), "human"))
	var s = _visit("station", 31, sh)
	var b = _view(s, true)
	check(b.picking, "the picker opens when there is crew to take")
	eq(b.pick_rows().size(), 3, "three can be picked from")
	var at: Vector2 = s.soldier.pos
	b.wasd_override = Vector2(1.0, 0.0)
	_step(b, 1.0)
	eq(s.soldier.pos, at, "he does not walk while it is up")
	b.toggle_pick(0)
	b.toggle_pick(1)
	b.toggle_pick(2)
	eq(b.pick.size(), 2, "the third is refused")
	b.toggle_pick(0)
	b.toggle_pick(2)
	b.confirm_party()
	check(not b.picking, "it closes")
	eq(s.party.size(), 2, "two came")
	eq(s.party.map(func(p): return p["src"].name), ["Tess", "Vik"], "the two picked")
	b.wasd_override = Vector2.ZERO
	b.leave()
	var alone = _visit("station", 31, _ship())
	var b2 = _view(alone, true)
	b2.confirm_party()
	eq(alone.party.size(), 0, "going alone is allowed")
	b2.leave()
	var nobody = _visit("station", 31, Ship.from_design(RUSTBUCKET))
	var b3 = _view(nobody, true)
	check(b3.picking and b3.pick_rows().is_empty(), "with nobody to take the picker still opens: it is how you go alone")
	b3.go_alone()
	b3.leave()


func test_the_trigger_fires_the_weapon_toward_the_aim_and_r_reloads() -> void:
	var s = _visit("station", 31)
	s.foes.list.clear()
	var b = _view(s)
	b.aim_override = (s.soldier.pos + Vector2(5.0, 0.0)) * 32.0
	b.fire_override = true
	_step(b, 1.0)
	b.fire_override = false
	check(s.gun()["mag"] < 8, "the trigger fired (%d left)" % s.gun()["mag"])
	s.reload()
	_step(b, 1.5)
	eq(s.gun()["mag"], 8, "reloaded")
	b._fire_wait = true  # a click that took something from a list is not a shot
	b.fire_override = true
	_step(b, 1.0)
	eq(s.gun()["mag"], 8, "the held button does not fire until it is let go")
	b.fire_override = false
	_step(b, 0.1)
	b.fire_override = true
	_step(b, 0.2)
	check(s.gun()["mag"] < 8, "and then it does")
	b.fire_override = false
	b.leave()


func test_holding_e_by_a_downed_follower_revives_him_in_four_seconds() -> void:
	var s = _with_party(1)
	var b = _view(s)
	var p: Dictionary = s.party[0]
	p["m"].hp = 0.0
	p["m"].pos = s.soldier.pos + Vector2(1.5, 0.0)
	b.e_override = true
	b.step(0.05)
	eq(str(b.target.get("type", "")), "revive", "E would revive him")
	_step(b, 3.0)
	check(p["m"].is_down(), "three seconds are not enough")
	_step(b, 1.5)
	check(not p["m"].is_down(), "four are")
	b.e_override = false
	b.leave()


func test_leaving_with_a_follower_down_asks_first() -> void:
	var s = _with_party(1)
	var b = _view(s)
	s.party[0]["m"].hp = 0.0
	s.party[0]["m"].pos = s.soldier.pos + Vector2(6.0, 0.0)
	b.step(0.05)
	eq(str(b.target.get("type", "")), "airlock", "he is at the airlock")
	b.e_override = false
	b.step(0.05)
	b.e_override = true
	b.step(0.05)
	check(b.active, "the first E only asks")
	check(b.message.contains("down"), "and says why: %s" % b.message)
	b.e_override = false
	b.step(0.05)
	b.e_override = true
	b.step(0.05)
	check(not b.active, "the second leaves")


func test_a_soldier_who_goes_down_fades_out_and_comes_to_on_the_ship() -> void:
	var s = _visit("station", 31)
	var b = _view(s)
	var got := []
	b.finished.connect(func(r): got.append(r))
	s.hurt_member(s.soldier, 999.0, Vector2.ZERO)
	_step(b, 1.0)
	check(b.active and s.downed, "the screen is fading")
	_step(b, 3.0)
	check(not b.active, "then he is back")
	eq(got.size(), 1, "told once")
	check(got[0]["downed"] and got[0]["cleared"], "closed for good")


func test_the_hollow_arrival_is_noticed_by_the_view() -> void:
	var s = _visit("station", 31)
	s.foes.list.clear()
	var b = _view(s)
	b.hollow_source = func() -> bool: return true
	_step(b, 0.2)
	check(s.hollow, "the visit knows the Hollow is here")
	check(s.foes.list.size() >= 2, "and it has people in it")
	b.leave()


func test_the_tracker_shows_what_moves_and_pings_by_distance() -> void:
	var s = _visit("station", 31)
	s.foes.list.clear()
	var spots: Array = s.foes._spots(12.0).filter(func(sp): return sp["pos"].distance_to(s.soldier.pos) < 22.0)
	check(not spots.is_empty(), "a spot 12 to 22 cells off")
	var f: Dictionary = s.foes.add("scavenger", spots[0]["pos"], spots[0]["room"])
	f["mode"] = "hunt"
	f["target"] = s.soldier.pos
	var b = _view(s)
	var far := []
	for i in 120:
		b.step(0.05)
		far.append_array(b.tracker.last_heard)  # (the view takes the pings itself, to sound them)
	check(far.size() >= 1, "a foe on the move is pinged (%d)" % far.size())
	check(far.all(func(x): return x >= 0.0 and x <= 1.0), "with how far out it was")
	b.leave()


# --- balance: how many he fights at once ------------------------------------------------------------------------

## Spots for `n` foes in the arena room: the foe spot and the free ones nearest it that have a clear line to the soldier.
func _spots_near(d: Dictionary, n: int) -> Array:
	var site = d["s"].site
	var out: Array = []
	var anchors: Array = site.free_anchors(d["room"])
	anchors.sort_custom(func(x, y): return (Vector2(x) + Vector2.ONE).distance_to(d["b"]) < (Vector2(y) + Vector2.ONE).distance_to(d["b"]))
	for a in anchors:
		var p := Vector2(a) + Vector2.ONE
		if p.distance_to(d["a"]) >= 5.0 and site.clear_line(d["a"], p) and out.all(func(q): return q.distance_to(p) >= 1.9):
			out.append(p)
			if out.size() == n:
				break
	return out


## A soldier who stands where he is, shoots the nearest foe he can see (a quarter of a second to take aim) and reloads when he must, for up to
## `seconds` or until nobody is left up or he is down. Returns the number of foes still up.
func _stand_and_shoot(s, seconds: float) -> int:
	var react := 0.0
	var seen = null
	var aim := 0.0
	for i in int(seconds / 0.05):
		var best = null
		var bd := INF
		for b in s.foes.bodies():
			var dist: float = s.soldier.pos.distance_to(b["pos"])
			if dist < bd and dist <= 12.0 and s.site.clear_line(s.soldier.pos, b["pos"]):
				best = b
				bd = dist
		var g: Dictionary = s.gun()
		if best != null:
			aim = (best["pos"] - s.soldier.pos).angle()
			if seen != best["ref"]:
				seen = best["ref"]
				react = 0.25
			react -= 0.05
			if react <= 0.0 and int(g["mag"]) > 0 and float(g["reload"]) <= 0.0:
				s.fire(aim)
		else:
			seen = null
		if int(g["mag"]) == 0 or (best == null and int(g["mag"]) < int(g["w"]["mag"])):
			s.reload()
		s.tick(0.05, aim, true)
		if s.soldier.is_down() or s.foes.live().is_empty():
			break
	return s.foes.live().size()


## A station fight in the biggest room: the soldier at `a`, three scavengers and a pirate at the spots near `b`, awake and coming `group` at a time
## (1: one after another, as a careful soldier takes them through a door; 4: all at once, as in the open). The others wait out of the way until
## the ones before them are down. Returns {hp, down, left, rounds}, {} when the site has no room for it.
func _station_fight(seed_value: int, group: int) -> Dictionary:
	var d := _arena("station", seed_value)
	var s = d["s"]
	if d["a"] == Vector2.ZERO:
		return {}
	var kinds := ["scavenger", "scavenger", "scavenger", "pirate"]
	var spots := _spots_near(d, kinds.size())
	if spots.size() < kinds.size():
		return {}
	var rounds: int = s.reserve() + s.gun()["mag"]
	var foes := []
	for i in kinds.size():
		var f: Dictionary = s.foes.add(kinds[i], spots[i], d["room"])
		f["base"] = (d["a"] - spots[i]).angle()
		foes.append(f)
	var next := 0
	while next < foes.size() and not s.soldier.is_down():
		for i in foes.size():
			var f: Dictionary = foes[i]
			var now: bool = i >= next and i < next + group
			if f["dead"]:
				continue
			f["m"].pos = spots[i] if i < next + group else Vector2(-100.0, -100.0)  # (the rest are not on the scene yet)
			if now and f["mode"] == "idle":
				f["mode"] = "hunt"
				f["target"] = d["a"]
		_stand_and_shoot(s, 25.0)
		next += group
	return {"hp": s.soldier.hp, "down": s.soldier.is_down(), "left": s.foes.live().size(), "rounds": rounds - (s.reserve() + s.gun()["mag"])}


func test_a_lone_soldier_with_a_pistol_beats_four_foes_one_at_a_time_and_loses_to_them_all_at_once() -> void:
	var stats := {}
	for group in [1, 2, 4]:
		var downs := 0
		var n := 0
		var hp := 0.0
		var rounds := 0
		for sd in 12:
			var r := _station_fight(sd * 3 + 1, group)
			if r.is_empty():
				continue
			n += 1
			downs += int(r["down"])
			hp += float(r["hp"])
			rounds = maxi(rounds, int(r["rounds"]))
		stats[group] = {"n": n, "downs": downs, "hp": hp / maxf(float(n), 1.0), "rounds": rounds}
	check(stats[1]["n"] >= 8, "enough sites have the room (%d)" % stats[1]["n"])
	eq(stats[1]["downs"], 0, "taken one at a time (a door, the beam) he is never down")
	check(stats[1]["hp"] >= 45.0, "and keeps about half his health (%.0f)" % stats[1]["hp"])
	check(stats[1]["rounds"] <= 30, "for no more than 30 of his 40 rounds (%d)" % stats[1]["rounds"])
	check(stats[2]["hp"] < stats[1]["hp"] - 15.0, "two at once cost much more (%.0f)" % stats[2]["hp"])
	check(float(stats[4]["downs"]) >= 0.7 * float(stats[4]["n"]), "all four at once in the open put him down (%d of %d)" % [stats[4]["downs"], stats[4]["n"]])
	check(stats[4]["hp"] < 15.0, "with next to nothing left (%.0f)" % stats[4]["hp"])


func test_a_melee_sidearm_swings_at_what_is_close_and_needs_no_rounds() -> void:
	var d := _arena()
	var s = d["s"]
	s.soldier.set_species("basalt")
	s._arm()
	eq(s.gun()["id"], "quarry_hammer", "a basalt soldier carries the hammer")
	check(not Arms.has_mag(s.gun()), "it has no magazine")
	var near: Dictionary = s.foes.add("scavenger", d["a"] + Vector2(1.6, 0.0), d["room"])
	var far: Dictionary = s.foes.add("scavenger", d["a"] + Vector2(4.0, 0.0), d["room"])
	var hp: float = near["m"].hp
	eq(s.fire(0.0), "swing", "he swings")
	check(near["m"].hp < hp - 20.0, "and the close one is hurt (%.0f of %.0f)" % [near["m"].hp, hp])
	eq(far["m"].hp, far["m"].max_hp, "the one four cells off is not")
	check(not s.reload(), "there is nothing to reload")
	s.tick(1.2)
	eq(s.fire(PI), "swing", "a swing at nothing is still a swing")
	check(s.take_events().any(func(e): return e["type"] == "swing"), "and the view is told")
