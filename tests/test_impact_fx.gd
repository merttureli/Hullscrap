extends "res://tests/base_test.gd"
## Ram and ricochet feedback (scripts/combat/impact_fx.gd, drawn by combat_view.gd): a real collision of the
## courier and the rammer gives a ram event with its contact points, and that event gives sparks, debris and
## a blast, a screen shake that grows with the impact energy and a chronicle line with the damage.

const ImpactFx = preload("res://scripts/combat/impact_fx.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")


## A fight that has run until the first ram event: the courier against the rammer, which charges it.
func _rammed() -> Session:
	var s := Session.new()
	s.start(Ship.from_design("res://data/ships/starter_courier.json"), Session.spawn_rammer(), 3)
	for i in 60 * 20:
		s.tick(1.0 / 60.0)
		if s.arena.events.any(func(e): return e["type"] == "ram"):
			break
	return s


func _ram_index(s: Session) -> int:
	for i in s.arena.events.size():
		if s.arena.events[i]["type"] == "ram":
			return i
	return -1


func test_a_ram_event_carries_the_contact_points() -> void:
	var s := _rammed()
	var i := _ram_index(s)
	check(i >= 0, "the rammer reached the courier")
	var e: Dictionary = s.arena.events[i]
	var pts: Array = e["points"]
	check(pts.size() >= 1 and pts.size() <= 6, "up to six contact points: %d" % pts.size())
	for p in pts:
		check(p is Vector2 and p.distance_to(e["pos"]) < 200.0, "each is a world point near the collision")


func test_a_ram_gives_sparks_debris_a_blast_and_a_line() -> void:
	var s := _rammed()
	var i := _ram_index(s)
	var e: Dictionary = s.arena.events[i]
	var r := ImpactFx.ram(s.arena, i, Session.PLAYER, "pirate")
	var fx: Array = r["fx"]
	var kinds := {}
	for f in fx:
		kinds[f["k"]] = int(kinds.get(f["k"], 0)) + 1
	check(kinds.get("spark", 0) > 0 and kinds.get("debris", 0) > 0, "sparks and debris: %s" % [kinds])
	var sparks := fx.filter(func(f): return f["k"] == "art" and f["name"] == "sparks")
	eq(sparks.size(), e["points"].size(), "the sparks art at every contact point")
	for k in sparks.size():
		eq(sparks[k]["pos"], e["points"][k], "at the point")
	var blasts := fx.filter(func(f): return f["k"] == "art" and f["name"] == "explosion")
	eq(blasts.size(), 1, "one small blast")
	eq(blasts[0]["pos"], e["pos"], "where the ships met")
	for f in fx:
		check(f["life"] > 0.0 and f.has("pos"), "every entry has a place and a life")
	check(r["shake"] >= ImpactFx.SHAKE_MIN and r["shake"] <= ImpactFx.SHAKE_MAX, "a shake in range: %s" % r["shake"])
	var line: String = r["line"]
	check(line.begins_with("Rammed the pirate: "), "the chronicle line (%s)" % line)
	check(line.contains(" hull damage") or line.contains("no hull damage"), "says the damage (%s)" % line)
	check(line.contains("(took "), "and what the ram cost us (%s)" % line)
	var chronicle: Array = s.arena.ships[Session.PLAYER].ship.events
	eq(chronicle.back()["text"], line, "the line is in the player's chronicle")
	var d: Dictionary = r["damage"]
	check(d.has(Session.PLAYER) and d.has(Session.ENEMY), "the damage each ship took is counted")


func test_the_damage_in_the_line_is_the_hull_hp_the_ram_hits_removed() -> void:
	var s := _rammed()
	var i := _ram_index(s)
	var want := {0: 0.0, 1: 0.0}
	for e in s.arena.events:
		if e["type"] == "hit" and e.get("ram", false) and e["tick"] == s.arena.events[i]["tick"] and e["kind"] != "component":
			want[e["ship"]] += e["dealt"]
	var d := ImpactFx.ram_damage(s.arena.events, i)
	for ship in [0, 1]:
		var got: float = d.get(ship, {}).get("hull", 0.0)
		check(absf(got - want[ship]) < 1e-6, "ship %d: %s hull damage, counted %s" % [ship, got, want[ship]])
	var line: String = ImpactFx.ram(s.arena, i, Session.PLAYER, "pirate")["line"]
	var dealt: float = d.get(Session.ENEMY, {}).get("hull", 0.0)
	check(line.contains(ImpactFx._hull_text(dealt)), "the enemy's share is in the line (%s)" % line)


func test_the_same_ram_looks_the_same() -> void:
	var s := _rammed()
	var i := _ram_index(s)
	var a := ImpactFx.ram(s.arena, i)
	var b := ImpactFx.ram(s.arena, i)
	eq(a["fx"], b["fx"], "the scatter is seeded from the event")
	eq(a["shake"], b["shake"], "and so is the shake")


func test_a_collision_that_is_not_ours_writes_no_line() -> void:
	var s := _rammed()
	var i := _ram_index(s)
	var before: int = s.arena.ships[Session.PLAYER].ship.events.size()
	eq(ImpactFx.ram(s.arena, i, 5, "pirate")["line"], "", "the player is in neither ship")
	eq(s.arena.ships[Session.PLAYER].ship.events.size(), before, "nothing logged")


func test_shake_and_effects_grow_with_the_impact_energy() -> void:
	eq(ImpactFx.shake(0.0), ImpactFx.SHAKE_MIN, "a bump: the least")
	eq(ImpactFx.shake(1.0e15), ImpactFx.SHAKE_MAX, "a huge hit: the most")
	var last := 0.0
	for e in [3.0e5, 1.0e6, 4.0e6, 1.6e7, 6.0e7]:
		var k := ImpactFx.shake(e)
		check(k >= last, "shake never falls as the energy rises (%s at %s)" % [k, e])
		last = k
	check(ImpactFx.shake(1.6e7) > ImpactFx.shake(4.0e5) + 5.0, "a hard ram shakes much more than a nudge")
	eq(ImpactFx.power(0.0), 0.2, "the smallest effects")
	eq(ImpactFx.power(1.0e15), 1.0, "the largest")
	var s := _rammed()
	var i := _ram_index(s)
	var big: Dictionary = s.arena.events[i].duplicate()
	big["energy"] = 1.0e8
	s.arena.events.append(big)
	var small: Dictionary = s.arena.events[i].duplicate()
	small["energy"] = 1.0e5
	s.arena.events.append(small)
	var n_big: int = ImpactFx.ram(s.arena, s.arena.events.size() - 2, 5)["fx"].size()
	var n_small: int = ImpactFx.ram(s.arena, s.arena.events.size() - 1, 5)["fx"].size()
	check(n_big > n_small, "a hard ram throws more sparks and debris (%d against %d)" % [n_big, n_small])


func test_a_ricochet_shows_a_small_spark_at_the_bounce_point() -> void:
	var e := {"tick": 40, "type": "ricochet", "ship": 1, "pos": Vector2(120, -40), "dir": Vector2.DOWN, "n": Vector2.UP, "new_dir": Vector2(0.6, -0.8)}
	var fx := ImpactFx.bounce(e)
	eq(fx[0]["name"], "sparks", "the sparks art")
	eq(fx[0]["pos"], Vector2(120, -40), "at the bounce point")
	check(fx[0]["scale"] < 0.6, "small")
	check(fx.size() >= 2 and fx[1]["k"] == "spark", "with a spark or two on the way out")
	check(fx[1]["vel"].normalized().dot(Vector2(0.6, -0.8)) > 0.8, "which flies the way the shot leaves")
	eq(ImpactFx.bounce(e), fx, "the same every time")


func test_the_view_turns_a_ram_into_effects_a_shake_and_a_note() -> void:
	var s := _rammed()
	var i := _ram_index(s)
	var view := CombatView.new()
	view.session = s
	view._cursor = i
	view._on_event(s.arena.events[i])
	check(view._fx.size() > 5, "effects were added: %d" % view._fx.size())
	check(view._shake >= ImpactFx.SHAKE_MIN, "the camera shakes: %s" % view._shake)
	check(view._note.begins_with("Rammed the pirate"), "a note says so (%s)" % view._note)
	var kinds := {}
	for f in view._fx:
		kinds[f["k"]] = true
	check(kinds.has("debris") and kinds.has("spark"), "debris and sparks reached the view: %s" % [kinds.keys()])
	var before: int = view._fx.size()
	view._on_event({"tick": 9, "type": "ricochet", "ship": 1, "pos": Vector2(5, 5), "dir": Vector2.DOWN, "n": Vector2.UP, "cell": Vector2i(1, 1)})
	check(view._fx.size() >= before + 3, "a ricochet adds its spark besides the streak and the flash")
	view.free()
