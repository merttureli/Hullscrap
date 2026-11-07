extends "res://tests/base_test.gd"
## Small fight-UI fixes: one ability box per key and ability (x2 for two parts), and the default LMB for a ship whose guns would leave it empty.

const Ship = preload("res://scripts/ship/ship.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const DESIGNS := "res://data/ships/starter_rustbucket.json"

func _ship(_key: String) -> Ship:
	return Session.load_ship(DESIGNS)


func test_the_rustbucket_gun_is_in_lmb_and_its_boxes_merge() -> void:
	var s := Session.new()
	s.start(_ship("Rustbucket"), Session.load_ship(DESIGNS), 3)
	eq(s.weapons().map(func(w): return w["group"]), [1], "the lone missile gun (kind default RMB) is in LMB: a new player's click fires")
	var comps = s.arena.ships[Session.PLAYER].ship.components
	comps.set_group_choice(s.weapons()[0]["uid"], 2)
	eq(s.weapons().map(func(w): return w["group"]), [2], "a saved choice never moves")
	var jets: Array = s.ability_boxes().filter(func(b): return b["count"] > 1)
	eq(jets.size(), 1, "two Kickjets: one Sputter Boost box")
	eq([jets[0]["count"], jets[0]["slots"].size(), jets[0]["key"]], [2, 2, "engine"], "x2 on the engine key")
	eq(s.ability_boxes().size(), s.ability_slots().size() - 1, "one box fewer than slots")


func test_default_lmb_only_when_lmb_is_empty() -> void:
	var ship := _ship("Rustbucket")
	var w = preload("res://scripts/combat/weapons.gd").new()
	var comps = ship.components
	var missile: int = comps.instances.keys().filter(func(u): return comps.instances[u]["id"] == "bolt_thrower_scrap")[0]
	eq(w.group_in(comps, missile), 1, "alone, the RMB gun takes LMB")
	comps.instances[9001] = {"id": "laser_mk1"}
	eq(w.group_in(comps, missile), 2, "a laser holds LMB: the missile keeps RMB")
	eq(w.group_in(comps, 9001), 1, "and the laser is in LMB")
	comps.instances[9001]["group"] = 2
	eq(w.group_in(comps, missile), 1, "the laser's saved RMB leaves LMB empty again")
	comps.instances.erase(9001)


func test_a_merged_ability_box_shows_ready_if_any_part_is_ready_else_the_shortest_cooldown() -> void:
	var ready := {"state": "ready", "cooldown_left": 0.0}
	var c5 := {"state": "cooling", "cooldown_left": 5.0}
	var c2 := {"state": "cooling", "cooldown_left": 2.0}
	eq(Session.merge_states([c5, ready, c2])["state"], "ready", "any ready part: READY")
	eq(Session.merge_states([c5, c2])["cooldown_left"], 2.0, "all cooling: the shortest wait")
	eq(Session.merge_states([c2, {"state": "active", "cooldown_left": 0.0}])["state"], "active", "one running: shown running")
