extends "res://tests/base_test.gd"
## The generic keys of the racial parts (scripts/sim/part_effects.gd, docs/CONTENT.md section 17): one test for each
## key, out of a fight and in one where it applies, the validator, the cons that a race's own traits cancel (a
## Basalt in a venting room, a Mire at a fire, a Fenn at a repair ...), and determinism. The parts are the existing
## ones with an ability put on them in the test, so the data has no racial part yet.

const Abilities = preload("res://scripts/sim/abilities.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Damage = preload("res://scripts/combat/damage.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Heat = preload("res://scripts/sim/heat.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const PartEffects = preload("res://scripts/sim/part_effects.gd")
const Reliability = preload("res://scripts/sim/reliability.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Stats = preload("res://scripts/sim/stats.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A passive ability list with `effects` and `side_effects`.
func _passive(effects := {}, side := []) -> Array:
	return [{"id": "t", "name": "T", "type": "passive", "effects": effects, "side_effects": side}]


## The test room with a reactor (x 10..13, y 10..13) and `part_id` turned round (x 15.., y 10..13), joined by one cable.
## `defs`: component id -> fields to set on that part's def in this ship ("stats" is merged into the existing stats).
## Returns {ship, reactor, part}.
func _rig(part_id: String, defs: Dictionary) -> Dictionary:
	var ship := Fixture.room_ship()
	for id in defs:
		for k in defs[id]:
			if k == "stats":
				ship.components.by_id[id]["stats"].merge(defs[id][k], true)
			else:
				ship.components.by_id[id][k] = defs[id][k]
	var d := {"ship": ship}
	d["reactor"] = Fixture.put(ship, "reactor_mk1", 10, 10)
	d["part"] = Fixture.put(ship, part_id, 15, 10, 2)
	Fixture.wire(ship, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	return d


## A person on body anchor (x, y); the player flag keeps the job board from moving them.
func _crew(ship: Ship, p_name: String, species: String, x: int, y: int) -> CrewMember:
	var m := CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)), species)
	m.is_player = true
	ship.crew.append(m)
	return m


func _put(m: CrewMember, x: int, y: int) -> void:
	m.pos = Pathfinder.centre_of(Vector2i(x, y))


## The sealed test room plus a second one under it (y 19..25), full of air.
func _two_rooms(ship: Ship) -> void:
	BuildSession.new(ship).apply(BuildSession.room_changes(Vector2i(8, 18), Vector2i(22, 26), "wall", "floor"))
	ship.refresh()
	for i in ship.atmosphere.pressure.size():
		ship.atmosphere.pressure[i] = 1.0


func _supply(ship: Ship) -> float:
	ship.refresh()
	var total := 0.0
	for n in ship.power_state["networks"]:
		total += n["supply"]
	return total


func _run(ship: Ship, seconds: float, step := 0.1) -> void:
	for i in roundi(seconds / step):
		Abilities.tick(ship, step)


# --- the validator ---------------------------------------------------------------------------------

func _who_ids() -> Array:
	var out := []
	for s in ["human", "kett", "mire", "gauntling", "prismatic", "mechanical"]:
		out.append(s)
	return out


func _bad(a: Dictionary, needle: String) -> void:
	var p := PartEffects.problems(a, _who_ids(), ["no_breath", "suit"])
	check(p.any(func(m): return needle in m), "'%s' is reported for %s, got %s" % [needle, str(a), str(p)])


func test_the_validator_accepts_every_key_of_the_racial_vocabulary() -> void:
	var a := {"id": "x", "name": "X", "type": "passive", "effects": {
		"stat_mult": {"thrust": 1.2}, "shield_layer": 1, "charge_mult": 0.9, "evasion_add": 0.1,
		"crew_bonus": {"who": "kett", "stat": "power", "per": 1, "max": 3},
		"crew_needed": [{"count": 3, "stat": "shield_layer", "else_mult": 0.5}, {"count": 1, "stat": "recharge", "else_mult": 0.25, "who": "mechanical|kett"}],
		"room_wall_hp_mult": 1.5, "heat_above": {"heat": 60, "shield_layer": 1},
		"room_work_mult": {"mult": 1.2, "who": "kett", "else_mult": 0.8}},
		"side_effects": [{"type": "shock_organic", "rate": 2}, {"type": "scorch", "rate": 1}, {"type": "wet", "rate": 0.8}, {"type": "heat", "rate": 5}],
		"operator_needs": ["no_breath|suit"]}
	eq(PartEffects.problems(a, _who_ids(), ["no_breath", "suit"]), [], "a full ability is fine")
	eq(PartEffects.problems({"id": "p", "type": "passive"}), [], "so is a bare passive")
	eq(PartEffects.problems({"id": "p", "type": "active", "duration": 5.0, "key": "engine"}), [], "and a bare active")
	eq(PartEffects.problems({"id": "p", "type": "passive", "effects": {"crew_bonus": [{"who": "kett", "stat": "power", "per": 1, "max": 3}, {"who": "human", "stat": "thrust", "per": 1, "max": 2}]}}), [], "crew_bonus as a list")


func test_the_validator_catches_unknown_keys_and_bad_values() -> void:
	_bad({"id": "x", "type": "passive", "speed": 2}, "unknown ability key 'speed'")
	_bad({"id": "x", "type": "passive", "effects": {"teleport": 1}}, "unknown effect 'teleport'")
	_bad({"id": "x", "type": "passive", "side_effects": [{"type": "explode", "rate": 1}]}, "unknown side effect type 'explode'")
	_bad({"id": "x", "type": "passive", "side_effects": [{"type": "wet", "rate": 0.8, "who": "kett"}]}, "unknown key 'who'")
	_bad({"id": "x", "type": "passive", "side_effects": [{"type": "wet", "rate": 1.5}]}, "fraction")
	_bad({"id": "x", "type": "passive", "side_effects": [{"type": "shock_organic"}]}, "needs a rate")
	_bad({"id": "x", "type": "passive", "side_effects": [{"type": "shock_organic", "rate": -1}]}, "needs a rate")
	_bad({"id": "x", "type": "passive", "side_effects": [{"type": "scorch"}]}, "needs a rate")
	_bad({"id": "x", "type": "passive", "side_effects": [{"type": "scorch", "rate": -2}]}, "needs a rate")
	_bad({"id": "x", "type": "passive", "side_effects": [{"type": "scorch", "rate": 1, "who": "human"}]}, "unknown key 'who'")
	_bad({"id": "x", "type": "active", "key": "engine"}, "needs a duration")
	_bad({"id": "x", "type": "passive", "key": "cargo"}, "key 'cargo'")
	_bad({"id": "x", "type": "ghost"}, "type must be")
	_bad({"type": "passive"}, "needs an id")
	_bad({"id": "x", "type": "passive", "operator_needs": ["no_such_trait"]}, "not a trait")
	var cb := {"who": "kett", "stat": "power", "per": 1, "max": 3}
	for k in [["who", "kett_typo", "not a species"], ["stat", "heat", "not one of"], ["per", 0, "above 0"], ["per", "1", "above 0"], ["max", -1, "above 0"], ["extra", 1, "unknown key 'extra'"]]:
		var e := cb.duplicate()
		e[k[0]] = k[1]
		_bad({"id": "x", "type": "passive", "effects": {"crew_bonus": e}}, k[2])
	for k in ["who", "stat", "per", "max"]:
		var e := cb.duplicate()
		e.erase(k)
		_bad({"id": "x", "type": "passive", "effects": {"crew_bonus": e}}, "needs '%s'" % k)
	_bad({"id": "x", "type": "passive", "effects": {"crew_bonus": {"who": "kett", "stat": "power", "per": 3, "max": 2}}}, "max is below per")
	var cn := {"count": 3, "stat": "power", "else_mult": 0.5}
	for k in [["count", 0, "whole number"], ["count", 1.5, "whole number"], ["stat", "fuel", "not one of"], ["else_mult", -1, "factor"], ["who", "nobody", "not a species"], ["extra", 1, "unknown key 'extra'"]]:
		var e := cn.duplicate()
		e[k[0]] = k[1]
		_bad({"id": "x", "type": "passive", "effects": {"crew_needed": e}}, k[2])
	for k in ["count", "stat", "else_mult"]:
		var e := cn.duplicate()
		e.erase(k)
		_bad({"id": "x", "type": "passive", "effects": {"crew_needed": e}}, "needs '%s'" % k)
	_bad({"id": "x", "type": "passive", "effects": {"room_wall_hp_mult": 0}}, "above 0")
	_bad({"id": "x", "type": "passive", "effects": {"room_wall_hp_mult": "1.5"}}, "above 0")
	_bad({"id": "x", "type": "passive", "effects": {"heat_above": {"heat": 60}}}, "needs 'shield_layer'")
	_bad({"id": "x", "type": "passive", "effects": {"heat_above": {"heat": 60, "shield_layer": 0.5}}}, "whole number")
	_bad({"id": "x", "type": "passive", "effects": {"heat_above": 60}}, "heat_above must be")
	_bad({"id": "x", "type": "passive", "effects": {"room_work_mult": {"mult": -1}}}, "mult must be")
	_bad({"id": "x", "type": "passive", "effects": {"room_work_mult": {"who": "kett"}}}, "needs 'mult'")
	_bad({"id": "x", "type": "passive", "effects": {"room_work_mult": {"mult": 1.2, "else_mult": 0.8}}}, "needs a who")
	_bad({"id": "x", "type": "passive", "effects": {"stat_mult": {"fuel": 2}}}, "not thrust or power")


func test_the_component_rules_catch_a_shield_effect_on_a_non_shield_and_a_bad_malfunction_stat() -> void:
	var fx := {"crew_needed": {"count": 2, "stat": "shield_layer", "else_mult": 0.5}}
	var ab := {"id": "x", "type": "passive", "effects": fx}
	eq(PartEffects.component_problems({"family": "shield", "abilities": [ab]}), [], "on a shield it is fine")
	check(not PartEffects.component_problems({"family": "reactor", "abilities": [ab]}).is_empty(), "on a reactor it does nothing, so it is refused")
	check(not PartEffects.component_problems({"family": "reactor", "abilities": [{"id": "x", "type": "passive", "effects": {"heat_above": {"heat": 5, "shield_layer": 1}}}]}).is_empty(), "heat_above too")
	eq(PartEffects.component_problems({"family": "reactor", "abilities": [{"id": "x", "type": "passive", "effects": {"crew_needed": {"count": 1, "stat": "power", "else_mult": 0.5}}}]}), [], "a power one is fine on a reactor")
	eq(PartEffects.component_problems({"family": "weapon", "stats": {"malfunction_per_min": 0.2}}), [], "a malfunction rate is a chance per minute")
	for bad in [1.5, -0.1, "often"]:
		check(not PartEffects.component_problems({"family": "weapon", "stats": {"malfunction_per_min": bad}}).is_empty(), "malfunction_per_min %s is refused" % str(bad))
	eq(PartEffects.component_problems({"family": "shield", "stats": {"layers": 1, "recharge": 1.4}}), [], "a recharge time is fine")
	for bad in [0, -1.0, "fast"]:
		check(not PartEffects.component_problems({"family": "shield", "stats": {"layers": 1, "recharge": bad}}).is_empty(), "recharge %s is refused" % str(bad))


# --- crew_bonus ------------------------------------------------------------------------------------

func test_crew_bonus_power_counts_matching_up_crew_in_the_room_up_to_max() -> void:
	var fx := {"crew_bonus": {"who": "kett", "stat": "power", "per": 1, "max": 3}}
	var d := _rig("oxygen_gen", {"reactor_mk1": {"abilities": _passive(fx)}})
	var ship: Ship = d["ship"]
	_two_rooms(ship)
	near(_supply(ship), 8.0, "a reactor 8 with nobody there")
	_crew(ship, "Human", "human", 12, 14)
	near(_supply(ship), 8.0, "a human is not a Kett")
	var k1 := _crew(ship, "K1", "kett", 12, 14)
	near(_supply(ship), 9.0, "one Kett: +1 (the refresh sees the crew, no tick needed)")
	var k2 := _crew(ship, "K2", "kett", 14, 14)
	var k3 := _crew(ship, "K3", "kett", 16, 14)
	near(_supply(ship), 11.0, "three Kett: +3")
	_crew(ship, "K4", "kett", 18, 14)
	near(_supply(ship), 11.0, "a fourth adds nothing: max 3")
	k3.hp = 0.0
	near(_supply(ship), 11.0, "a downed one leaves three standing")
	k2.stun = 2.0
	near(_supply(ship), 10.0, "a stunned one does not count either")
	_put(k1, 12, 22)
	near(_supply(ship), 9.0, "one in the other room is not in the part's room")
	_put(k1, 12, 14)
	near(_supply(ship), 10.0, "and counts again when it walks back")


func test_crew_bonus_power_runs_a_consumer_that_the_base_could_not_in_a_fight_too() -> void:
	var fx := {"crew_bonus": {"who": "kett", "stat": "power", "per": 1, "max": 3}}
	var d := _rig("oxygen_gen", {"reactor_mk1": {"abilities": _passive(fx)}, "oxygen_gen": {"power": -9}})
	var ship: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(ship)
	check(not a.ships[0].powered.get(d["part"], false), "9 wanted of 8: unpowered")
	var k := _crew(ship, "K1", "kett", 12, 14)
	a.step(0.05)
	check(a.ships[0].powered.get(d["part"], false), "a Kett walks in: 9 of 9, the arena sees it")
	_put(k, 12, 4)  # off the floor, in no room
	a.step(0.05)
	check(not a.ships[0].powered.get(d["part"], false), "and out again")


func test_crew_bonus_thrust_adds_to_the_engine_in_a_fight_and_out_of_one() -> void:
	var fx := {"crew_bonus": {"who": "human", "stat": "thrust", "per": 2, "max": 4}}
	var d := _rig("engine_mk1", {"engine_mk1": {"abilities": _passive(fx)}})
	var ship: Ship = d["ship"]
	eq(Abilities.thrust_boost(ship), {}, "nobody there: no boost")
	_crew(ship, "A", "human", 12, 14)
	near(Abilities.thrust_boost(ship)[d["part"]], 1.2, "one human: (10 + 2) / 10, out of a fight")
	var a := Arena.new(1)
	a.add_ship(ship)
	near(a.ships[0].thrust, 12.0, "the arena starts at 12")
	_crew(ship, "B", "human", 16, 14)
	_crew(ship, "C", "human", 18, 14)
	a.step(0.05)
	near(a.ships[0].thrust, 14.0, "three walk in: 10 + 4 (max), and the arena refreshed by itself")


func test_crew_bonus_shield_layer_adds_whole_layers() -> void:
	var fx := {"crew_bonus": {"who": "prismatic", "stat": "shield_layer", "per": 1, "max": 2}}
	var d := _rig("shield_mk1", {"shield_mk1": {"abilities": _passive(fx)}})
	var ship: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(ship)
	eq([a.ships[0].layers_cap, a.ships[0].layers], [1, 1], "one layer to begin with")
	_crew(ship, "P1", "prismatic", 12, 14)
	a.step(0.05)
	eq([a.ships[0].layers_cap, a.ships[0].layers], [2, 2], "a Prismatic walks in: a second layer, up at once")
	_crew(ship, "P2", "prismatic", 14, 14)
	_crew(ship, "P3", "prismatic", 16, 14)
	a.step(0.05)
	eq(a.ships[0].layers_cap, 3, "two Prismatics are worth the max of 2 more")
	eq(Shields.layers_of_ship(ship, a.ships[0].powered), 3, "and the panel's count agrees")


# --- crew_needed -----------------------------------------------------------------------------------

func test_crew_needed_power_cuts_a_reactor_that_lacks_its_crew() -> void:
	var fx := {"crew_needed": {"count": 2, "stat": "power", "else_mult": 0.5}}
	var d := _rig("oxygen_gen", {"reactor_mk1": {"abilities": _passive(fx)}})
	var ship: Ship = d["ship"]
	near(_supply(ship), 4.0, "an empty room: 8 x 0.5")
	var a := _crew(ship, "A", "human", 12, 14)
	near(_supply(ship), 4.0, "one of two")
	var b := _crew(ship, "B", "human", 14, 14)
	near(_supply(ship), 8.0, "two of two: full power")
	b.stun = 1.0
	near(_supply(ship), 4.0, "a stunned one does not count")
	b.stun = 0.0
	a.hp = 0.0
	near(_supply(ship), 4.0, "nor a downed one")


func test_crew_needed_with_who_counts_only_those_it_names() -> void:
	var fx := {"crew_needed": {"count": 1, "stat": "power", "else_mult": 0.25, "who": "mechanical"}}
	var d := _rig("oxygen_gen", {"reactor_mk1": {"abilities": _passive(fx)}})
	var ship: Ship = d["ship"]
	_crew(ship, "H", "human", 12, 14)
	near(_supply(ship), 2.0, "a human is not mechanical: 8 x 0.25")
	_crew(ship, "G", "gauntling", 14, 14)
	near(_supply(ship), 8.0, "a Gauntling is (the flag of its traits, and its trait id)")


func test_crew_needed_thrust_is_the_overclock_engine() -> void:
	var fx := {"stat_mult": {"thrust": 1.5}, "crew_needed": {"count": 1, "stat": "thrust", "else_mult": 0.6666667, "who": "mechanical"}}
	var d := _rig("engine_mk1", {"engine_mk1": {"abilities": _passive(fx)}})
	var ship: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(ship)
	near(a.ships[0].thrust, 10.0, "no Gauntling aboard: x1.5 x 2/3 = x1")
	var g := _crew(ship, "G", "gauntling", 12, 14)
	a.step(0.05)
	near(a.ships[0].thrust, 15.0, "a Gauntling in the room: x1.5")
	_put(g, 12, 4)
	a.step(0.05)
	near(a.ships[0].thrust, 10.0, "and it goes away")


func test_crew_needed_shield_layer_is_the_hive_battery() -> void:
	var fx := {"crew_needed": {"count": 3, "stat": "shield_layer", "else_mult": 0.5}}
	var d := _rig("shield_mk1", {"shield_mk1": {"abilities": _passive(fx), "stats": {"layers": 4}}})
	var ship: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(ship)
	eq([a.ships[0].layers_cap, a.ships[0].layers], [2, 2], "nobody there: 4 x 0.5 = 2 layers")
	_crew(ship, "A", "kett", 12, 14)
	_crew(ship, "B", "kett", 14, 14)
	a.step(0.05)
	eq(a.ships[0].layers_cap, 2, "two of three")
	var c := _crew(ship, "C", "kett", 16, 14)
	a.step(0.05)
	eq([a.ships[0].layers_cap, a.ships[0].layers], [4, 4], "three: all four layers, up at once")
	_put(c, 12, 4)
	a.step(0.05)
	eq([a.ships[0].layers_cap, a.ships[0].layers], [2, 2], "one leaves: two layers, the lost ones dropped")
	d = _rig("shield_mk1", {"shield_mk1": {"abilities": _passive({"crew_needed": {"count": 1, "stat": "shield_layer", "else_mult": 0.5}}), "stats": {"layers": 1}}})
	eq(Shields.layers_of_ship(d["ship"], d["ship"].power_state["powered"]), 0, "layers round down: 1 x 0.5 = 0")


func test_crew_needed_recharge_slows_the_layers_coming_back() -> void:
	var fx := {"crew_needed": {"count": 2, "stat": "recharge", "else_mult": 0.5}}
	var back := []
	for crew in [0, 2]:
		var d := _rig("shield_mk1", {"shield_mk1": {"abilities": _passive(fx)}})
		var ship: Ship = d["ship"]
		for i in crew:
			_crew(ship, "C%d" % i, "human", 12 + 2 * i, 14)
		var a := Arena.new(1)
		a.add_ship(ship)
		Shields.absorb(a, 0, {"damage_type": "energy"})
		eq(a.ships[0].layers, 0, "the layer is used")
		var t := 0.0
		while a.ships[0].layers == 0 and t < 30.0:
			a.step(0.1)
			t += 0.1
		back.append(t)
	var usual := Abilities.shield_base() + Abilities.shield_break_delay()  # the one layer is the sector's last: 3 s more
	near(back[1], usual, "with the crew it is back after the usual 7 s + 3 s", 0.15)
	near(back[0], 2.0 * usual, "without it, at half speed the layer and the wait both take twice as long: 20 s", 0.15)
	var d2 := _rig("shield_mk1", {"shield_mk1": {"abilities": _passive({"crew_needed": {"count": 1, "stat": "recharge", "else_mult": 0.0}})}})
	var a2 := Arena.new(1)
	a2.add_ship(d2["ship"])
	Shields.absorb(a2, 0, {"damage_type": "energy"})
	a2.step(20.0)
	eq(a2.ships[0].layers, 0, "else_mult 0: the layer never comes back until the crew is there")
	_crew(d2["ship"], "C", "human", 12, 14)
	a2.step(10.1)
	eq(a2.ships[0].layers, 1, "and it comes back once they are")


func test_crew_needed_evasion_is_the_resonance_helm() -> void:
	var fx := {"evasion_add": 0.1, "crew_needed": {"count": 1, "stat": "evasion", "else_mult": 0.0, "who": "prismatic"}}
	var d := _rig("helm", {"helm": {"abilities": _passive(fx)}})
	var ship: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(ship)
	var base: float = a.weapons.evasion(a, 0)
	near(Abilities.evasion_add(ship), 0.0, "no Prismatic aboard: the helm adds nothing")
	_crew(ship, "H", "human", 12, 14)
	near(Abilities.evasion_add(ship), 0.0, "a human at the helm neither")
	var p := _crew(ship, "P", "prismatic", 14, 14)
	near(Abilities.evasion_add(ship), 0.1, "a Prismatic in the room: +0.1")
	near(a.weapons.evasion(a, 0) - base, 0.1, "and the arena's evasion has it")
	p.hp = 0.0
	near(Abilities.evasion_add(ship), 0.0, "a downed one does not")


# --- stats.recharge --------------------------------------------------------------------------------

## Seconds until sector 0 of a shield part has its used layer back (40 at most).
func _back_after(ship: Ship) -> float:
	var a := Arena.new(1)
	a.add_ship(ship)
	Shields.absorb(a, 0, {"damage_type": "energy"}, Vector2.ZERO, Vector2.ZERO, 0)
	var before: float = a.ships[0].sector_layers[0]
	var t := 0.0
	while a.ships[0].sector_layers[0] < before + 1.0 - 1e-6 and t < 40.0:
		a.step(0.05)
		t += 0.05
	return t


func test_stats_recharge_sets_how_fast_a_used_layer_comes_back() -> void:
	var times := {}
	var all := Abilities.shield_base() + Abilities.shield_break_delay()  # the one layer is the sector's last: it waits 3 s more (at the part's speed)
	for recharge in [7.0, 3.5, 14.0]:
		var d := _rig("shield_mk1", {"shield_mk1": {"stats": {"recharge": recharge}}})
		times[recharge] = _back_after(d["ship"])
	near(times[7.0], all, "7.0 is the normal 7 s (+ 3)", 0.1)
	near(times[3.5], all / 2.0, "3.5 comes back in half the time", 0.1)
	near(times[14.0], all * 2.0, "14.0 takes twice as long", 0.1)
	var d2 := _rig("shield_mk1", {})
	d2["ship"].components.by_id["shield_mk1"]["stats"].erase("recharge")
	near(_back_after(d2["ship"]), all, "a shield with no stats.recharge is normal", 0.1)


func test_the_neon_lattice_shield_recharges_in_its_4_seconds() -> void:
	var d := _rig("shield_neon_mk1", {})
	var ship: Ship = d["ship"]
	near(Abilities.recharge_rate(ship, ship.power_state["powered"]), 7.0 / 4.0, "x1.75", 1e-6)
	near(_back_after(ship), 4.0, "a used layer is back after 4 s", 0.1)


func test_crew_needed_recharge_multiplies_the_parts_own_speed_and_several_shields_average_by_layers() -> void:
	var fx := {"crew_needed": {"count": 1, "stat": "recharge", "else_mult": 0.5}}
	var d := _rig("shield_mk1", {"shield_mk1": {"abilities": _passive(fx), "stats": {"recharge": 3.5}}})
	var ship: Ship = d["ship"]
	near(Abilities.recharge_rate(ship, ship.power_state["powered"]), 1.0, "x2 from the part, x0.5 for no crew")
	_crew(ship, "C", "human", 12, 14)
	near(Abilities.recharge_rate(ship, ship.power_state["powered"]), 2.0, "x2 with the crew there")
	_two_rooms(ship)
	var neon := Fixture.put(ship, "shield_neon_mk1", 10, 20)
	var rate := Abilities.recharge_rate(ship, {d["part"]: true, neon: true})
	near(rate, (1.0 * 2.0 + 2.0 * (7.0 / 4.0)) / 3.0, "a 1-layer x2 and a 2-layer x1.75 average by layers", 1e-6)
	near(Abilities.recharge_rate(ship, {}), 1.0, "no powered shield: 1")


# --- room_wall_hp_mult -----------------------------------------------------------------------------

func test_room_wall_hp_mult_toughens_the_walls_round_the_room_when_a_fight_starts() -> void:
	var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({"room_wall_hp_mult": 1.5})}})
	var ship: Ship = d["ship"]
	_two_rooms(ship)
	near(ship.grid.hp_of(Vector2i(8, 12)), 4.0, "a wall is 4 hp before the fight")
	var a := Arena.new(1)
	a.add_ship(ship)
	near(ship.grid.hp_of(Vector2i(8, 12)), 6.0, "x1.5 on the room's west wall")
	near(ship.grid.hp_of(Vector2i(15, 8)), 6.0, "and its north wall")
	near(ship.grid.hp_of(Vector2i(22, 12)), 6.0, "and its east wall")
	near(ship.grid.hp_of(Vector2i(8, 22)), 4.0, "the other room's walls are as they were")
	near(ship.grid.hp_of(Vector2i(15, 17)), 6.0, "the south wall, shared with the other room's neighbour row, bounds the first")
	near(ship.grid.hp_of(Vector2i(15, 18)), 4.0, "while the other room's own north wall is plain")
	var co = a.ships[0]
	var cell := Vector2i(8, 12)
	Damage.apply(a, 0, cell, Damage.solid_at(co, cell), 5.0, "kinetic")
	eq(ship.grid.get_tile(cell), "wall", "5 damage does not breach a 6 hp wall")
	near(ship.grid.hp_of(cell), 1.0, "it has 1 hp left")
	cell = Vector2i(8, 22)
	Damage.apply(a, 0, cell, Damage.solid_at(co, cell), 5.0, "kinetic")
	eq(ship.grid.get_tile(cell), "", "the same shot breaches a plain 4 hp wall")


func test_room_wall_hp_mult_needs_a_working_part_skips_doors_and_does_not_stack() -> void:
	var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({"room_wall_hp_mult": 1.5})}})
	var ship: Ship = d["ship"]
	ship.components.instances[d["part"]]["status"] = "disabled"
	eq(Abilities.wall_hp_mults(ship), {}, "a disabled bay does nothing")
	ship.components.instances[d["part"]]["status"] = "ok"
	ship.grid.force_tile(Vector2i(8, 12), "door")
	ship.mark_dirty()
	var m := Abilities.wall_hp_mults(ship)
	check(not m.has(Vector2i(8, 12)), "a door is not a wall")
	near(float(m[Vector2i(8, 13)]), 1.5, "the walls beside it are")
	Fixture.put(ship, "oxygen_gen", 18, 10, 2)
	Fixture.wire(ship, [Vector2i(16, 11), Vector2i(17, 11), Vector2i(18, 11)])
	m = Abilities.wall_hp_mults(ship)
	near(float(m[Vector2i(8, 13)]), 1.5, "two bays in one room: still x1.5, they do not stack")
	var a := Arena.new(1)
	a.add_ship(Fixture.room_ship())
	eq(a.ships[0].ship.grid.hp_mult, {}, "a ship with no bay has no factors")


func test_the_wall_factor_is_not_saved_and_a_later_fight_without_the_bay_is_plain() -> void:
	var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({"room_wall_hp_mult": 2.0})}})
	var ship: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(ship)
	near(ship.grid.hp_of(Vector2i(8, 12)), 8.0, "x2")
	check(not ship.grid.to_dict().has("hp_mult"), "the factor is not in the save")
	ship.components.remove_uid(d["part"])
	var b := Arena.new(1)
	b.add_ship(ship)
	near(ship.grid.hp_of(Vector2i(8, 12)), 4.0, "the bay was taken out: the next fight has plain walls")


# --- heat_above ------------------------------------------------------------------------------------

func test_heat_above_gives_a_layer_while_the_room_is_hot() -> void:
	var fx := {"heat_above": {"heat": 60, "shield_layer": 1}}
	var d := _rig("shield_mk1", {"shield_mk1": {"abilities": _passive(fx)}})
	var ship: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(ship)
	eq([a.ships[0].layers_cap, a.ships[0].layers], [1, 1], "cool: one layer")
	ship.components.instances[d["part"]]["heat"] = 60.0
	a.step(0.05)
	eq(a.ships[0].layers_cap, 1, "exactly 60 is not above")
	ship.components.instances[d["part"]]["heat"] = 61.0
	a.step(0.05)
	eq([a.ships[0].layers_cap, a.ships[0].layers], [2, 2], "above 60: a second layer, up at once")
	ship.components.instances[d["reactor"]]["heat"] = 90.0  # another part of the same room
	ship.components.instances[d["part"]]["heat"] = 10.0
	a.step(0.05)
	eq(a.ships[0].layers_cap, 2, "the room's hottest part counts, not the shield's own")
	ship.components.instances[d["reactor"]]["heat"] = 0.0
	a.step(0.05)
	eq([a.ships[0].layers_cap, a.ships[0].layers], [1, 1], "cooled: back to one")


# --- room_work_mult --------------------------------------------------------------------------------

func test_room_work_mult_scales_the_work_of_the_crew_in_the_room() -> void:
	var fx := {"room_work_mult": {"mult": 1.2, "who": "kett", "else_mult": 0.8}}
	var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive(fx)}})
	var ship: Ship = d["ship"]
	_two_rooms(ship)
	var kett := _crew(ship, "K", "kett", 12, 14)
	var human := _crew(ship, "H", "human", 14, 14)
	var away := _crew(ship, "A", "human", 12, 22)
	for kind in ["repair_component", "extinguish", "repair_breach", "revive"]:
		near(Jobs._work_rate(ship, kett, kind), 1.2, "a Kett on %s" % kind)
		near(Jobs._work_rate(ship, human, kind), 0.8, "a human on %s" % kind)
		near(Jobs._work_rate(ship, away, kind), 1.0, "someone in the other room on %s" % kind)
	ship.components.instances[d["part"]]["status"] = "malfunction"
	near(Jobs._work_rate(ship, human, "repair_component"), 1.0, "a part that is out of action does nothing")


func test_room_work_mult_without_who_is_for_everybody_and_stacks_with_the_traits() -> void:
	var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({"room_work_mult": {"mult": 2.0}})}})
	var ship: Ship = d["ship"]
	var fenn := _crew(ship, "F", "fenn", 12, 14)  # fast_repair: 1 / 0.6
	var human := _crew(ship, "H", "human", 14, 14)
	near(Jobs._work_rate(ship, human, "repair_component"), 2.0, "everybody x2")
	near(Jobs._work_rate(ship, fenn, "repair_component"), 2.0 / 0.6, "a Fenn's quick hands on top (Quickfix Bay)", 1e-5)
	d = _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({"room_work_mult": {"mult": 2.0}})}})
	var ship2: Ship = d["ship"]
	var h2 := _crew(ship2, "H", "human", 14, 14)
	var jobs := Jobs.new()
	var uid := Fixture.put(ship2, "engine_mk1", 15, 14)
	ship2.components.instances[uid]["status"] = "malfunction"
	var job := jobs._fix_job(ship2, uid)
	jobs.work(ship2, h2, job, 1.0)
	near(jobs.progress[job["key"]], 2.0, "the real repair job moves at that speed")


# --- shock_organic ---------------------------------------------------------------------------------

func test_shock_organic_hurts_the_crew_in_the_room_who_are_not_mechanical() -> void:
	var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({}, [{"type": "shock_organic", "rate": 2.0}])}})
	var ship: Ship = d["ship"]
	_two_rooms(ship)
	var human := _crew(ship, "H", "human", 12, 14)
	var gaunt := _crew(ship, "G", "gauntling", 14, 14)
	var away := _crew(ship, "A", "human", 12, 22)
	var downed := _crew(ship, "D", "human", 16, 14)
	downed.hp = 0.0
	var sim := ShipSim.new()
	sim.ships = [ship]
	sim._step_ship(ship, 1.0)
	near(human.hp, 98.0, "a human takes 2 hp a second (out of a fight, ShipSim ticks it)")
	near(gaunt.hp, 100.0, "a Gauntling is mechanical: nothing")
	near(away.hp, 100.0, "the other room is safe")
	near(downed.hp, 0.0, "a downed one is left alone")
	ship.components.instances[d["part"]]["status"] = "disabled"
	sim._step_ship(ship, 1.0)
	near(human.hp, 98.0, "no shock from a part that is out of action")


func test_shock_organic_runs_in_a_fight_and_drops_a_crew_member_once() -> void:
	var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({}, [{"type": "shock_organic", "rate": 3.0}])}})
	var ship: Ship = d["ship"]
	var human := _crew(ship, "H", "human", 12, 14)
	human.hp = 4.0
	var a := Arena.new(1)
	a.add_ship(ship)
	a.step(1.0)
	near(human.hp, 1.0, "3 hp in the arena's second")
	a.step(1.0)
	near(human.hp, 0.0, "down")
	var downs := ship.events.filter(func(e): return e["text"] == "H is down")
	eq(downs.size(), 1, "the chronicle says so once")
	a.step(1.0)
	eq(ship.events.filter(func(e): return e["text"] == "H is down").size(), 1, "and not again")


# --- scorch ----------------------------------------------------------------------------------------

func test_scorch_burns_the_crew_in_the_room_who_are_not_heat_resistant() -> void:
	var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({}, [{"type": "scorch", "rate": 2.0}])}})
	var ship: Ship = d["ship"]
	_two_rooms(ship)
	var human := _crew(ship, "H", "human", 12, 14)
	var ember := _crew(ship, "E", "emberkin", 14, 14)
	var mire := _crew(ship, "M", "mire", 16, 14)
	var gaunt := _crew(ship, "G", "gauntling", 18, 14)  # mechanical, but not heat resistant
	var away := _crew(ship, "A", "human", 12, 22)
	var downed := _crew(ship, "D", "human", 20, 14)
	downed.hp = 0.0
	var sim := ShipSim.new()
	sim.ships = [ship]
	sim._step_ship(ship, 1.0)
	near(human.hp, 98.0, "a human takes 2 hp a second (out of a fight, ShipSim ticks it)")
	near(ember.max_hp - ember.hp, 0.0, "an Emberkin (heat_resistant) takes nothing")
	near(mire.hp, 98.0, "a Mire is not heat resistant")
	near(gaunt.hp, 98.0, "nor is a Gauntling: scorch is not shock_organic")
	near(away.hp, 100.0, "the other room is safe")
	near(downed.hp, 0.0, "a downed one is left alone")
	ship.components.instances[d["part"]]["status"] = "disabled"
	sim._step_ship(ship, 1.0)
	near(human.hp, 98.0, "no scorch from a part that is out of action")


func test_scorch_runs_in_a_fight_and_a_personal_heat_resistant_trait_counts() -> void:
	var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({}, [{"type": "scorch", "rate": 3.0}])}})
	var ship: Ship = d["ship"]
	var human := _crew(ship, "H", "human", 12, 14)
	var geared := _crew(ship, "S", "human", 14, 14)
	geared.gear_traits = ["heat_resistant"]  # a fire suit
	var ember := _crew(ship, "E", "emberkin", 16, 14)
	human.hp = 4.0
	var a := Arena.new(1)
	a.add_ship(ship)
	a.step(1.0)
	near(human.hp, 1.0, "3 hp in the arena's second")
	near(geared.hp, 100.0, "the human in heat-resistant gear is spared")
	near(ember.hp, ember.max_hp, "so is the Emberkin")
	a.step(1.0)
	near(human.hp, 0.0, "down")
	eq(ship.events.filter(func(e): return e["text"] == "H is down").size(), 1, "the chronicle says so once")


func test_a_pyre_drive_pairs_heat_with_scorch_and_only_the_emberkin_crew_runs_it_free() -> void:
	var lost := {}
	var state := {}
	for species in ["human", "emberkin"]:
		var d := _rig("engine_mk1", {"engine_mk1": {"abilities": _passive({"stat_mult": {"thrust": 1.5}}, [{"type": "heat", "rate": 1.0}, {"type": "scorch", "rate": 1.0}])}})
		var ship: Ship = d["ship"]
		var m := _crew(ship, "Wren", species, 17, 14)
		for i in 100:
			Abilities.tick(ship, 0.1)
			Heat.tick(ship, 0.1)
		lost[species] = m.max_hp - m.hp
		state[species] = ship.components.instances[d["part"]]["status"]
	near(lost["human"], 10.0, "a mixed crew pays 1 hp a second for the 10 s")
	near(lost["emberkin"], 0.0, "an Emberkin crew pays nothing")
	eq([state["human"], state["emberkin"]], ["ok", "ok"], "and the engine is the same for both (a mild heat here)")


# --- wet -------------------------------------------------------------------------------------------

func test_wet_slows_the_work_of_everyone_but_the_firefighters() -> void:
	var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({}, [{"type": "wet", "rate": 0.8}])}})
	var ship: Ship = d["ship"]
	_two_rooms(ship)
	var human := _crew(ship, "H", "human", 12, 14)
	var mire := _crew(ship, "M", "mire", 14, 14)
	var away := _crew(ship, "A", "human", 12, 22)
	near(Jobs._work_rate(ship, human, "repair_component"), 0.8, "a human works x0.8")
	near(Jobs._work_rate(ship, human, "extinguish"), 0.8, "at everything")
	near(Jobs._work_rate(ship, mire, "extinguish"), 2.0, "a Mire (extinguish x2) is not slowed")
	near(Jobs._work_rate(ship, mire, "repair_component"), 1.0, "at anything")
	near(Jobs._work_rate(ship, away, "repair_component"), 1.0, "the other room is dry")


func test_wet_cools_every_part_in_the_room_at_the_start_of_each_second() -> void:
	var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({}, [{"type": "wet", "rate": 0.8}])}})
	var ship: Ship = d["ship"]
	_two_rooms(ship)
	var far := Fixture.put(ship, "shield_mk1", 10, 20)
	for uid in [d["reactor"], d["part"], far]:
		ship.components.instances[uid]["heat"] = 80.0
	Abilities.tick(ship, 0.4)
	near(ship.components.instances[d["reactor"]]["heat"], 50.0, "the first second starts with -30 at once")
	near(ship.components.instances[d["part"]]["heat"], 50.0, "on the wet part too")
	near(ship.components.instances[far]["heat"], 80.0, "a part in the other room is not touched")
	Abilities.tick(ship, 0.4)
	near(ship.components.instances[d["reactor"]]["heat"], 50.0, "not again within the second")
	Abilities.tick(ship, 0.4)
	near(ship.components.instances[d["reactor"]]["heat"], 20.0, "the next second starts (1.2 s in): -30 again")
	for i in 5:
		Abilities.tick(ship, 1.0)
	near(ship.components.instances[d["reactor"]]["heat"], 0.0, "never below 0")


func test_wet_runs_in_a_fight() -> void:
	var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({}, [{"type": "wet", "rate": 0.5}])}})
	var ship: Ship = d["ship"]
	var human := _crew(ship, "H", "human", 12, 14)
	ship.components.instances[d["reactor"]]["heat"] = 90.0
	var a := Arena.new(1)
	a.add_ship(ship)
	a.step(0.1)
	near(ship.components.instances[d["reactor"]]["heat"], 60.0, "the arena ticks it")
	near(Jobs._work_rate(ship, human, "repair_component"), 0.5, "and the work factor is on")


# --- stats.malfunction_per_min ---------------------------------------------------------------------

func test_a_stats_malfunction_rate_replaces_the_lines() -> void:
	var ship := Fixture.room_ship()
	near(ship.effective("engine_mk1")["malfunction_per_min"], 0.01, "a standard engine: the line's 0.01")
	near(ship.effective("engine_scrap_mk1")["malfunction_per_min"], 0.15, "a scrap one: 0.15")
	ship.components.by_id["engine_mk1"]["stats"]["malfunction_per_min"] = 0.2
	ship.components.by_id["engine_scrap_mk1"]["stats"]["malfunction_per_min"] = 0.0
	near(ship.effective("engine_mk1")["malfunction_per_min"], 0.2, "the part's own 0.2 wins")
	near(ship.effective("engine_scrap_mk1")["malfunction_per_min"], 0.0, "even when it is 0")
	near(Stats.view(ship.components, ship.lines).def("engine_mk1")["stats"]["malfunction_per_min"], 0.2, "the stat stays in the stats")


func test_the_stat_malfunction_rate_is_what_reliability_rolls() -> void:
	var d := _rig("engine_mk1", {"engine_mk1": {"stats": {"malfunction_per_min": 1.0}}})
	var ship: Ship = d["ship"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	Reliability.tick(ship, 60.0, rng)
	eq(ship.components.instances[d["part"]]["status"], "malfunction", "1.0 a minute over a minute is certain")
	var e := _rig("engine_mk1", {})
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	Reliability.tick(e["ship"], 60.0, rng2)
	eq(e["ship"].components.instances[e["part"]]["status"], "ok", "the standard line (0.01 a minute) does not")


# --- the cons a race's own traits cancel -----------------------------------------------------------

func _venting_ship(species: String) -> Array:
	var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({}, [{"type": "drain_o2", "rate": 1.0}])}})
	var ship: Ship = d["ship"]
	var m := _crew(ship, "Wren", species, 12, 14)
	return [ship, m]


func test_basalt_do_not_suffer_a_part_that_drains_the_air_and_humans_do() -> void:
	var hp := {}
	for species in ["human", "basalt", "gauntling"]:
		var r := _venting_ship(species)
		var ship: Ship = r[0]
		var jobs := Jobs.new()
		for i in 60:
			Abilities.tick(ship, 0.5)
			jobs._health(ship, 0.5)
		hp[species] = r[1].hp
		check(ship.atmosphere.pressure_at(r[1].cell()) < 0.01, "%s: the air is gone" % species)
	check(hp["human"] < 50.0, "a human suffocates in a Vacuum Forge room: %s" % hp["human"])
	near(hp["basalt"], 140.0, "a Basalt (o2_use 0) loses nothing")
	check(hp["gauntling"] < 100.0, "a Gauntling still suffocates (half lungs only breathe less)")


func test_a_hot_part_trips_for_any_crew_and_only_the_fire_it_starts_is_cancelled_by_emberkin() -> void:
	var lost := {}
	var tripped := {}
	for species in ["human", "emberkin", "mire"]:
		var d := _rig("engine_mk1", {"engine_mk1": {"abilities": _passive({}, [{"type": "heat", "rate": 40.0}])}})
		var ship: Ship = d["ship"]
		var m := _crew(ship, "Wren", species, 17, 14)  # beside the engine, in its room
		var jobs := Jobs.new()
		for i in 40:  # 4 s: 40 heat a second takes the part to its limit in under 3
			Abilities.tick(ship, 0.1)
			Heat.tick(ship, 0.1)
			jobs._health(ship, 0.1)
		tripped[species] = ship.components.instances[d["part"]]["status"]
		lost[species] = m.max_hp - m.hp
		ship.components.instances[d["part"]]["heat"] = 0.0  # cooled again: only the fire is left to compare
		if species != "mire":
			near(m.hp, m.max_hp, "%s: a hot room hurts nobody by itself" % species)
		var burn := _crew(ship, "Burn", species, 12, 14)
		burn.hp = burn.max_hp
		Fire.ignite(ship, burn.cell())
		var before := burn.hp
		jobs._health(ship, 1.0)
		lost["burn_" + species] = before - burn.hp
	for species in ["human", "emberkin", "mire"]:
		eq(tripped[species], "overheated", "%s: the part overheats whoever is aboard" % species)
	near(lost["human"], 0.0, "a human is not hurt by the hot room")
	near(lost["emberkin"], 0.0, "an Emberkin neither")
	check(lost["mire"] > 0.0, "only a Mire (dries_out) is: %s" % lost["mire"])
	near(lost["burn_emberkin"], lost["burn_human"] * 0.25, "when it starts a fire an Emberkin takes a quarter of the burn")
	near(lost["burn_mire"], lost["burn_human"] * 0.5, "a Mire half")
	check(lost["burn_human"] > 0.0, "a human burns")


func test_a_mire_puts_out_the_fire_a_leaky_part_starts_twice_as_fast_and_burns_half() -> void:
	var seconds := {}
	for species in ["human", "mire"]:
		var d := _rig("oxygen_gen", {"oxygen_gen": {"abilities": _passive({}, [{"type": "fire_risk", "rate": 1.0}])}})
		var ship: Ship = d["ship"]
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		Abilities.tick(ship, 1.0, rng)
		check(not ship.fires.is_empty(), "%s: the part started a fire" % species)
		var cell: Vector2i = ship.fires.keys()[0]
		ship.fires[cell] = 1.0
		var m := _crew(ship, "Wren", species, 12, 14)
		var jobs := Jobs.new()
		var job := {"type": "extinguish", "key": "fire:%d,%d" % [cell.x, cell.y], "cell": cell}
		var t := 0.0
		while ship.fires.has(cell) and t < 20.0:
			jobs.work(ship, m, job, 0.1)
			t += 0.1
		seconds[species] = t
	near(seconds["mire"] * 2.0, seconds["human"], "a Mire needs half the time", 0.25)
	check(seconds["human"] > 1.0, "and it takes a human a while: %s s" % seconds["human"])


func test_a_fenn_repairs_a_self_damaging_or_unreliable_part_faster() -> void:
	var seconds := {}
	for species in ["human", "fenn"]:
		var d := _rig("engine_mk1", {"engine_mk1": {"abilities": _passive({}, [{"type": "self_damage", "rate": 0.5}]), "stats": {"malfunction_per_min": 0.2}}})
		var ship: Ship = d["ship"]
		var hp0 := float(ship.components.instances[d["part"]]["hp"])
		Abilities.tick(ship, 4.0)
		var inst: Dictionary = ship.components.instances[d["part"]]
		near(float(inst["hp"]), hp0 - 2.0, "%s: the part wore 0.5 hp a second whoever is aboard" % species)
		inst["status"] = "malfunction"
		var m := _crew(ship, "Wren", species, 17, 14)
		var jobs := Jobs.new()
		var job := jobs._fix_job(ship, d["part"])
		var t := 0.0
		while ship.components.instances[d["part"]]["status"] != "ok" and t < 30.0:
			jobs.work(ship, m, job, 0.1)
			t += 0.1
		seconds[species] = t
	var part := float(Jobs.jcfg()["repair_component"]["seconds"])  # data/crew.json: 12 s
	near(seconds["human"], part, "a human mends it in the job's time", 0.15)
	near(seconds["fenn"], part * 0.6, "a Fenn in 0.6 of it (x1/0.6)", 0.15)


func test_a_gauntling_is_not_shocked_by_its_own_reactor_and_a_mixed_crew_is() -> void:
	var d := _rig("oxygen_gen", {"reactor_mk1": {"abilities": _passive({"crew_bonus": {"who": "gauntling", "stat": "power", "per": 1, "max": 2}}, [{"type": "shock_organic", "rate": 1.0}])}})
	var ship: Ship = d["ship"]
	var g1 := _crew(ship, "G1", "gauntling", 12, 14)
	var g2 := _crew(ship, "G2", "gauntling", 14, 14)
	var h := _crew(ship, "H", "human", 16, 14)
	Abilities.tick(ship, 5.0)
	near(g1.hp + g2.hp, 200.0, "an all-Gauntling crew pays nothing")
	near(h.hp, 95.0, "a human aboard pays 1 hp a second")
	near(_supply(ship), 10.0, "and the Gauntlings are worth +2 power")


# --- determinism -----------------------------------------------------------------------------------

func _scenario() -> Array:
	var fx_r := {"crew_bonus": {"who": "kett", "stat": "power", "per": 1, "max": 3}}
	var fx_s := {"crew_needed": {"count": 2, "stat": "shield_layer", "else_mult": 0.5}, "heat_above": {"heat": 30, "shield_layer": 1}, "room_wall_hp_mult": 1.5}
	var d := _rig("shield_mk1", {"reactor_mk1": {"abilities": _passive(fx_r, [{"type": "shock_organic", "rate": 1.0}, {"type": "wet", "rate": 0.9}])},
		"shield_mk1": {"abilities": _passive(fx_s), "stats": {"layers": 2}}})
	var ship: Ship = d["ship"]
	var kett := _crew(ship, "K", "kett", 12, 14)
	var human := _crew(ship, "H", "human", 16, 14)
	var gaunt := _crew(ship, "G", "gauntling", 18, 14)
	var a := Arena.new(5)
	a.add_ship(ship)
	var out := []
	for second in 12:
		if second == 3:
			_put(kett, 18, 12)
		if second == 6:
			_put(human, 12, 4)
		if second == 8:
			ship.components.instances[d["part"]]["heat"] = 55.0
		for i in 10:
			a.step(0.1)
			Heat.tick(ship, 0.1)
		out.append([a.ships[0].layers_cap, a.ships[0].layers, _supply(ship), human.hp, kett.hp, gaunt.hp, ship.components.instances[d["part"]]["heat"], a.ships[0].thrust])
	out.append(ship.grid.hp_of(Vector2i(8, 12)))
	out.append(hash(str(a.snapshot())))
	return out


func test_the_same_scenario_replays_exactly() -> void:
	var first := _scenario()
	var second := _scenario()
	eq(first, second, "two runs of crew walking in and out of a room full of racial parts")
	check(first.size() > 12 and first[0][0] >= 1, "and it did something: %s" % str(first[0]))
	check(first[11][3] < 100.0 and first[11][5] == 100.0, "the human was shocked, the Gauntling was not")
