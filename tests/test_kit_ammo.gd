extends "res://tests/base_test.gd"
## Rounds (Beta 4.1): every starter's hold has 10; a follower shoots from a COPY of the soldier's spare rounds (floor follower_ammo_min), spends them, is OUT at none,
## and what is left is not added to the hold.

const Site = preload("res://scripts/board/site.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Party = preload("res://scripts/board/party.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _ship(rounds: int) -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.crew.append(CrewMember.new("Rook", Vector2(10, 10), "human"))
	s.crew.append(CrewMember.new("Tess", Vector2(12, 10), "fenn"))
	s.inventory.add("hand_ammo", rounds - s.inventory.count("hand_ammo"))
	return s


## A visit with one follower (Rook), no foes, and a spot for the soldier and one for a foe in the biggest room: {s, p, a, b, room}.
func _arena(rounds: int) -> Dictionary:
	var sh := _ship(rounds)
	var s = Boarding.start(null, null, "p31", {"kind": "station"}, sh)
	s.site = Site.make(31, "station", {"faction": "clans"})
	s.soldier.pos = s.site.airlock["spawn"]
	s.foes = Foes.new(s)
	s.foes.spawn_site({})
	s.foes.list.clear()
	var best := -1
	var most := 0
	for r in s.site.rooms:
		if r["purpose"] == "gone" or r["corridor"] or s.foes._red.has(r["id"]):
			continue
		var n: int = s.site.free_anchors(r["id"]).size()
		if n > most:
			most = n
			best = r["id"]
	var anchors: Array = s.site.free_anchors(best)
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	for x in anchors:
		for y in anchors:
			var pa := Vector2(x) + Vector2.ONE
			var pb := Vector2(y) + Vector2.ONE
			var d := pa.distance_to(pb)
			if a == Vector2.ZERO and d >= 6.0 and d <= 8.0 and s.site.clear_line(pa, pb):
				a = pa
				b = pb
	s.join_party(["Rook"])
	var p: Dictionary = s.party[0]
	p["m"].pos = a
	s.soldier.pos = a + Vector2(1.0, 0.0)
	return {"s": s, "p": p, "a": a, "b": b, "room": best}


func _run(s, seconds: float) -> void:
	for i in int(seconds / 0.05):
		s.tick(0.05, 0.0, false)


func _foe(d: Dictionary) -> Dictionary:
	var f: Dictionary = d["s"].foes.add("pirate", d["b"], d["room"])
	f["base"] = (d["a"] - d["b"]).angle() + 3.0
	return f


func test_every_starter_has_ten_rounds() -> void:
	var files: Array = []
	for f in DirAccess.get_files_at("res://data/ships"):
		if f.begins_with("starter_") and f.ends_with(".json"):
			files.append("res://data/ships/" + f)
	for f in DirAccess.get_files_at("res://data/packs/starters_2/ships"):
		if f.ends_with(".json"):
			files.append("res://data/packs/starters_2/ships/" + f)
	check(files.size() >= 30, "thirty starters (%d)" % files.size())
	for f in files:
		var s = Ship.from_design(f)
		check(s != null and s.inventory.count("hand_ammo") >= 10, "%s starts with 10 rounds" % f)


func test_a_follower_gets_a_copy_of_the_spare_rounds() -> void:
	var d := _arena(24)
	var s = d["s"]
	var p: Dictionary = d["p"]
	var spare: int = s.reserve()
	check(spare > 0, "the soldier has rounds in the hold (%d)" % spare)
	if Arms.has_mag(p["gun"]):
		eq(Party.rounds(p), maxi(spare + 0, 10), "the follower holds a copy of the spare rounds")
		eq(int(p["gun"]["mag"]), mini(int(p["gun"]["w"]["mag"]), spare), "loaded")
	eq(s.reserve(), spare, "nothing came out of the hold")


func test_the_floor_is_ten_rounds() -> void:
	for rounds in [0, 3]:
		var d := _arena(rounds)
		var p: Dictionary = d["p"]
		check(Arms.has_mag(p["gun"]), "Rook's sidearm has a magazine")
		eq(Party.rounds(p), maxi(d["s"].reserve(), 10), "%d spare: the follower still has 10" % rounds)
		eq(int(p["gun"]["mag"]) + int(p["rest"]), 10 if d["s"].reserve() < 10 else d["s"].reserve(), "(magazine and rest add up)")


func test_a_follower_spends_rounds_and_the_hold_stays() -> void:
	var d := _arena(30)
	var s = d["s"]
	var p: Dictionary = d["p"]
	var hold: int = s.reserve()
	var before := Party.rounds(p)
	var f := _foe(d)
	var hp: float = f["m"].hp
	_run(s, 4.0)
	check(Party.rounds(p) < before, "rounds were spent (%d of %d)" % [Party.rounds(p), before])
	check(f["m"].hp < hp or f["dead"], "and they hit")
	eq(s.reserve(), hold, "the hold did not pay for them")


func test_a_follower_reloads_from_their_own_rounds() -> void:
	var d := _arena(30)
	var s = d["s"]
	var p: Dictionary = d["p"]
	p["gun"]["mag"] = 0
	p["rest"] = 12
	var f := _foe(d)
	_run(s, 4.0)
	check(Party.rounds(p) < 12, "they reloaded and fired (%d)" % Party.rounds(p))
	check(f["m"].hp < f["m"].max_hp or f["dead"], "and it was hit")


func test_with_none_left_they_do_not_shoot_and_say_so_once() -> void:
	var d := _arena(30)
	var s = d["s"]
	var p: Dictionary = d["p"]
	p["gun"]["mag"] = 0
	p["rest"] = 0
	var f := _foe(d)
	var hp: float = f["m"].hp
	var hold: int = s.reserve()
	_run(s, 4.0)
	eq(f["m"].hp, hp, "an empty follower does not shoot")
	eq(Party.rounds(p), 0, "still nothing")
	check(bool(p["out"]), "marked OUT")
	var said: Array = s.events.filter(func(e): return str(e.get("text", "")) == "%s is out of rounds." % p["m"].name)
	eq(said.size(), 1, "the toast comes once")
	eq(s.reserve(), hold, "the hold was not drawn on")


func test_a_melee_follower_swings_and_needs_no_rounds() -> void:
	var d := _arena(30)
	var s = d["s"]
	var p: Dictionary = d["p"]
	p["gun"] = Arms.make_gun("ember_knife", false)
	Party.give_ammo(p, s.reserve())
	eq(Party.rounds(p), -1, "no magazine, no rounds")
	var f := _foe(d)
	f["m"].pos = d["a"] + Vector2(1.5, 0.0)
	var hp: float = f["m"].hp
	_run(s, 3.0)
	check(f["m"].hp < hp or f["dead"], "the knife landed")
	check(not bool(p["out"]), "never OUT")


func test_what_is_left_is_gone_and_never_added_to_the_hold() -> void:
	var d := _arena(30)
	var s = d["s"]
	var p: Dictionary = d["p"]
	p["rest"] = 9
	var sh = s.ship
	var soldiers := 0
	for g in s.guns:
		soldiers += int(g["mag"])
	var want: int = s.reserve() + soldiers  # his own magazines come home, theirs do not
	s.leave()
	eq(sh.inventory.count("hand_ammo"), want, "the follower's rounds did not come back")
