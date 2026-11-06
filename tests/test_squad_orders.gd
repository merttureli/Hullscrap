extends "res://tests/base_test.gd"
## Squad orders (scripts/board/orders.gd, party.gd): send the followers to a room, they fight, loot and hold it; recall, selection, the low-health fall back, locks
## and air, and a follower on Follow closing in on a foe it sees beyond its weapon's reach. Logic only.

const Site = preload("res://scripts/board/site.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Party = preload("res://scripts/board/party.gd")
const Air = preload("res://scripts/board/air.gd")
const Orders = preload("res://scripts/board/orders.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.crew.append(CrewMember.new("Rook", Vector2(10, 10), "human"))
	s.crew.append(CrewMember.new("Tess", Vector2(12, 10), "fenn"))
	return s


## A station visit with the two followers, no foes. `locked`: wants a room only a lock opens (else an open room with containers).
func _squad(locked := false) -> Dictionary:
	for seed_value in range(31, 80):
		var sh := _ship()
		var s = Boarding.start(null, null, "p%d" % seed_value, {"kind": "station"}, sh)
		s.site = Site.make(seed_value, "station", {"faction": "clans", "gen": "classic"})
		s.soldier.pos = s.site.airlock["spawn"]
		s.foes = Foes.new(s)
		s.foes.spawn_site({})
		s.foes.list.clear()
		var open: Dictionary = s.site.reachable_rooms(["hack", "card"])
		var any: Dictionary = s.site.reachable_rooms([])
		for r in s.site.rooms:
			var id: int = r["id"]
			if r["purpose"] in ["gone", "airlock", "corridor"] or id == int(s.site.airlock["room"]):
				continue
			var loot: Array = s.site.props.filter(func(q): return q["loot"] and int(q["room"]) == id)
			if loot.is_empty() or s.site.air_of(id) < 1.0:
				continue
			if open.has(id) != not locked or (locked and not any.has(id)):
				continue
			s.join_party(Party.eligible(sh).map(func(m): return m.name).slice(0, 2))
			return {"s": s, "room": id, "loot": loot.map(func(q): return q["id"])}
	return {}


func _run(s, seconds: float, dt := 0.05) -> void:
	for i in int(seconds / dt):
		s.tick(dt, 0.0, false)


func test_an_order_moves_a_follower_into_the_room() -> void:
	var d := _squad()
	check(not d.is_empty(), "a room with containers is open")
	var s = d["s"]
	check(s.site.room_at(s.party[0]["m"].pos) != d["room"], "it starts outside")
	check(Orders.send(s, d["room"]).contains("go to"), "the order is given and answered")
	_run(s, 45.0)
	for p in s.party:
		eq(s.site.room_at(p["m"].pos), d["room"], "%s is in the room" % p["m"].name)


func test_with_no_foe_the_room_is_looted_into_the_haul() -> void:
	var d := _squad()
	var s = d["s"]
	var before: int = s.ship.inventory.counts.size()
	Orders.send(s, d["room"])
	_run(s, 150.0)
	for id in d["loot"]:
		check(s.opened.has(id) and not s.left.has(id), "container %d was emptied" % id)
	check(s.said.size() > 0, "the haul is told")
	check(s.ship.inventory.counts.size() >= before, "and it reached the hold")
	var st := ""
	for p in s.party:
		st += Orders.state(s, p) + "|"
	check(st.contains("Holding: "), "then they hold the room (%s)" % st)
	check(s.party.all(func(p): return not bool(p["order"]["claim"])), "nobody is left on a container")


func test_a_foe_in_the_room_means_a_fight_first() -> void:
	var d := _squad()
	var s = d["s"]
	var at: Vector2 = s.site.centre_of_room(d["room"])
	var f: Dictionary = s.foes.add("pirate", _anchor_near(s, at), d["room"])
	var hp: float = f["m"].hp
	Orders.send(s, d["room"])
	var fought := false
	for i in 1200:
		s.tick(0.05, 0.0, false)
		for p in s.party:
			if Orders.state(s, p) == "Fighting":
				fought = true
	check(fought, "a follower said Fighting")
	check(f["dead"] or f["m"].hp < hp, "and hurt the foe (%.0f of %.0f)" % [f["m"].hp, hp])


func _anchor_near(s, p: Vector2) -> Vector2:
	var best := p
	var bd := INF
	for a in s.site.free_anchors(s.site.room_at(p)):
		var c := Vector2(a) + Vector2.ONE
		if c.distance_to(p) < bd:
			bd = c.distance_to(p)
			best = c
	return best


func test_a_lock_is_not_opened_by_a_follower() -> void:
	var d := _squad(true)
	if d.is_empty():
		return  # (no site in the seeds has a loot room behind a lock)
	var s = d["s"]
	Orders.send(s, d["room"])
	_run(s, 90.0)
	check(s.unlocked.is_empty(), "no door was unlocked")
	for p in s.party:
		check(s.site.room_at(p["m"].pos) != d["room"], "%s stayed out" % p["m"].name)
	check(s.party.any(func(p): return Orders.state(s, p) == "Can't enter: locked"), "and says why: %s" % Orders.state(s, s.party[0]))
	for id in d["loot"]:
		check(not s.opened.has(id), "container %d is untouched" % id)


func test_without_a_suit_a_follower_stops_at_an_airless_room() -> void:
	var d := _squad()
	var s = d["s"]
	s.site.rooms[d["room"]]["air"] = 0.0
	var bare := -1
	for i in s.party.size():
		if not Air.sealed(s.party[i]["m"]):
			bare = i
	check(bare >= 0, "one of them has no suit")
	Orders.select(s, bare)
	Orders.send(s, d["room"])
	_run(s, 60.0)
	var p: Dictionary = s.party[bare]
	check(s.site.room_at(p["m"].pos) != d["room"], "%s did not go in" % p["m"].name)
	eq(Orders.state(s, p), "Can't enter: no air", "and says why")
	check(not p["m"].is_down() and p["m"].hp >= p["m"].max_hp, "it is not choking")


func test_recall_makes_them_follow_again() -> void:
	var d := _squad()
	var s = d["s"]
	Orders.send(s, d["room"])
	_run(s, 30.0)
	check(Orders.recall(s).contains("follow"), "the recall is answered")
	check(s.party.all(func(p): return p.get("order", {}).is_empty()), "no orders are left")
	s.soldier.pos = s.site.airlock["spawn"]
	_run(s, 40.0)
	for p in s.party:
		check(p["m"].pos.distance_to(s.soldier.pos) <= 7.0, "%s is back with him (%.1f)" % [p["m"].name, p["m"].pos.distance_to(s.soldier.pos)])
		eq(Orders.state(s, p), "Following", "and follows")


func test_at_a_quarter_health_a_follower_falls_back() -> void:
	var d := _squad()
	var s = d["s"]
	Orders.send(s, d["room"])
	_run(s, 5.0)
	var p: Dictionary = s.party[0]
	p["m"].hp = p["m"].max_hp * 0.25
	_run(s, 0.1)
	check(p.get("order", {}).is_empty(), "its order is dropped")
	eq(Orders.state(s, p), "Falling back", "and it says so")
	check(not s.party[1].get("order", {}).is_empty(), "the other keeps its order")
	p["m"].hp = p["m"].max_hp
	_run(s, 0.1)
	eq(Orders.state(s, p), "Following", "mended, it follows")


func test_an_order_goes_to_the_selected_follower_only() -> void:
	var d := _squad()
	var s = d["s"]
	Orders.select(s, 1)
	Orders.send(s, d["room"])
	check(s.party[0].get("order", {}).is_empty(), "the unselected stays on follow")
	check(not s.party[1].get("order", {}).is_empty(), "the selected goes")
	Orders.select(s, 1)
	check(not bool(s.party[1]["sel"]), "clicking it again deselects")
	Orders.select(s, 0)
	Orders.select(s, 1, true)
	check(bool(s.party[0]["sel"]) and bool(s.party[1]["sel"]), "shift adds")
	Orders.recall(s)
	Orders.select(s, 0)
	Orders.select(s, 1)
	check(not bool(s.party[0]["sel"]) and bool(s.party[1]["sel"]), "a plain select replaces")


func test_a_follower_on_follow_closes_in_on_a_foe_beyond_its_reach() -> void:
	var found := false
	for seed_value in range(31, 60):
		var sh := _ship()
		var s = Boarding.start(null, null, "p%d" % seed_value, {"kind": "station"}, sh)
		s.site = Site.make(seed_value, "station", {"faction": "clans", "gen": "classic"})
		s.foes = Foes.new(s)
		s.foes.spawn_site({})
		s.foes.list.clear()
		for r in s.site.rooms:
			if r["purpose"] == "gone":
				continue
			var anchors: Array = s.site.free_anchors(r["id"])
			for a in anchors:
				for b in anchors:
					var pa := Vector2(a) + Vector2.ONE
					var pb := Vector2(b) + Vector2.ONE
					if found or pa.distance_to(pb) < 11.0 or pa.distance_to(pb) > 13.0 or not s.site.clear_line(pa, pb):
						continue
					found = true
					s.soldier.pos = pa
					s.join_party(Party.eligible(sh).map(func(m): return m.name).slice(0, 1))
					var p: Dictionary = s.party[0]
					p["m"].pos = pa + (pb - pa).normalized() * 1.0
					var reach: float = p["gun"]["w"]["range"]
					check(p["m"].pos.distance_to(pb) > reach, "the foe is past its weapon's reach (%.1f > %.1f)" % [p["m"].pos.distance_to(pb), reach])
					var f: Dictionary = s.foes.add("pirate", pb, r["id"])
					f["base"] = (pa - pb).angle() + 3.0
					var hp: float = f["m"].hp
					_run(s, 12.0)
					check(f["dead"] or f["m"].hp < hp, "it closed in and shot (%.0f of %.0f)" % [f["m"].hp, hp])
		if found:
			break
	check(found, "a long clear line exists in the seeds")
