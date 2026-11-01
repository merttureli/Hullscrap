extends "res://tests/base_test.gd"
## Racial tech, group a, the 15 components (data/packs/tech_<race>/components.json; the keys are the ones of
## docs/CONTENT.md section 17, built in scripts/sim/part_effects.gd). Each part is what the spec says, does its
## pro through the real code, and its con is paid by a mixed crew and cancelled by the race's own traits: a Basalt
## in a venting room, a Fenn at a repair, a Kett in a nest. The weapons of the same packs are in test_tech_data_a.gd.

const Abilities = preload("res://scripts/sim/abilities.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Collisions = preload("res://scripts/combat/collisions.gd")
const Content = preload("res://scripts/data/content.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Heat = preload("res://scripts/sim/heat.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const PartEffects = preload("res://scripts/sim/part_effects.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Radar = preload("res://scripts/space/radar.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")

const KEY_MATERIALS: Array[String] = ["military_circuit", "gate_alloy", "void_crystal", "nanite_paste"]
const HOMELAND := {"human": "human_core", "basalt": "basalt_quarries", "emberkin": "emberkin_forges", "fenn": "fenn_bazaar", "kett": "kett_hives"}
## id -> [family, tier, [w, h], power, priority]
const PARTS := {
	"human_reactor_plus": ["reactor", 1, [2, 4], 10, 0], "human_comms_array": ["utility", 1, [2, 2], -2, 3],
	"human_crew_quarters_deluxe": ["medbay", 1, [2, 2], -1, 3],
	"basalt_vacuum_forge": ["reactor", 1, [2, 4], 12, 0], "basalt_stonehide_bay": ["utility", 2, [2, 2], -1, 3],
	"basalt_gravity_anchor": ["utility", 2, [2, 2], -2, 3],
	"emberkin_pyre_drive": ["engine", 2, [2, 2], -3, 4], "emberkin_furnace_core": ["reactor", 1, [2, 4], 11, 0],
	"emberkin_hearth_shield": ["shield", 2, [2, 4], -4, 3],
	"fenn_haggle_engine": ["engine", 2, [2, 2], -3, 4], "fenn_jury_reactor": ["reactor", 1, [2, 4], 11, 0],
	"fenn_quickfix_bay": ["utility", 1, [2, 2], -2, 3],
	"kett_hive_battery": ["shield", 2, [2, 4], -5, 3], "kett_nest_reactor": ["reactor", 1, [2, 4], 8, 0],
	"kett_brood_hold": ["utility", 1, [2, 2], -1, 3],
}


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## The test room with a Reactor Mk1 (x 10..13, y 10..13) and `part_id` (x 15.., y 10..) joined by cables; a second room
## under it (y 19..25) full of air, for crew who must be elsewhere. Returns {ship, reactor, part}.
func _rig(part_id: String, rot := 2) -> Dictionary:
	var ship := Fixture.room_ship()
	var d := {"ship": ship}
	d["reactor"] = Fixture.put(ship, "reactor_mk1", 10, 10)
	d["part"] = Fixture.put(ship, part_id, 15, 10, rot)
	Fixture.wire(ship, [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	BuildSession.new(ship).apply(BuildSession.room_changes(Vector2i(8, 18), Vector2i(22, 26), "wall", "floor"))
	ship.refresh()
	for i in ship.atmosphere.pressure.size():
		ship.atmosphere.pressure[i] = 1.0
	return d


func _crew(ship: Ship, p_name: String, species: String, x: int, y: int) -> CrewMember:
	var m := CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)), species)
	m.is_player = true  # the job board does not move them
	ship.crew.append(m)
	return m


func _supply(ship: Ship) -> float:
	ship.refresh()
	var total := 0.0
	for n in ship.power_state["networks"]:
		total += n["supply"]
	return total


## `seconds` of the part effects and the crew's health, as the sim runs them (heat too when `heat`). True when some
## part was overheated at any step (a tripped part cools and comes back, so the end state does not say).
func _run(ship: Ship, seconds: float, heat := false, step := 0.5) -> bool:
	var jobs := Jobs.new()
	var tripped := false
	for i in roundi(seconds / step):
		Abilities.tick(ship, step)
		if heat:
			Heat.tick(ship, step)
		jobs._health(ship, step)
		for uid in ship.components.instances:
			tripped = tripped or ship.components.instances[uid]["status"] == "overheated"
	return tripped


func _status(d: Dictionary) -> String:
	return str(d["ship"].components.instances[d["part"]]["status"])


# --- the shape, the recipe and the validator -------------------------------------------------------------------

func test_every_part_is_what_the_spec_says() -> void:
	var per := {}
	for id in PARTS:
		var want: Array = PARTS[id]
		var race: String = id.split("_")[0]
		per[race] = int(per.get(race, 0)) + 1
		eq(Content.origin("components", id), "tech_" + race, id + ": from the race's pack")
		var c := Content.entry("components", id)
		eq([c["family"], int(c["tier"]), int(c["size"][0]), int(c["size"][1]), int(c["power"]), int(c["priority"]), c["line"]], [want[0], want[1], want[2][0], want[2][1], want[3], want[4], "standard"], id + ": family, tier, size, power, priority, line")
		check(str(c.get("blurb", "")).length() > 20 and str(c.get("quirk", "")).length() > 20, id + ": a blurb and a quirk line")
		check(not c.get("unique", false), id + " is not unique")
		eq(PartEffects.component_problems(c, [], []), [], id + ": passes the ability validator")
		if c["family"] == "engine":
			eq([int(c["mount"]["outside"][0]), int(c["mount"]["outside"][1])], [4, 2], id + ": an engine with a 4x2 outside half")
	for r in ["human", "basalt", "emberkin", "fenn", "kett"]:
		eq(per.get(r, 0), 3, r + ": three components")


func test_the_recipes_are_fab_level_two_with_no_key_material() -> void:
	for id in PARTS:
		var r := Content.entry("recipes", id)
		eq(Content.origin("recipes", id), "tech_" + id.split("_")[0], id + ": its recipe is in the pack")
		eq(int(r["fab_level"]), 2, id + ": fab level 2")
		for m in r["materials"]:
			check(not m in KEY_MATERIALS, "%s: no key material below tier 3 (%s)" % [id, m])
	var plus: Dictionary = Content.entry("recipes", "human_reactor_plus")["materials"]
	var base: Dictionary = Content.entry("recipes", "reactor_mk1")["materials"]
	for m in base:
		near(float(plus[m]), float(base[m]) * 1.2, "the Reactor Plus costs 20 percent more of " + m, 0.01)


func test_the_homeland_stores_sell_the_components() -> void:
	for id in PARTS:
		var race: String = id.split("_")[0]
		var region = JSON.parse_string(FileAccess.get_file_as_string("res://data/regions/%s.json" % HOMELAND[race]))
		check(region["stock"].has(id) and float(region["stock"][id]) > 0.0, "%s is in the stock of %s" % [id, HOMELAND[race]])


# --- reactors ----------------------------------------------------------------------------------------------------

func test_the_reactors_make_what_the_spec_says_over_a_reactor_mk1() -> void:
	var want := {"human_reactor_plus": 1.0, "basalt_vacuum_forge": 3.0, "emberkin_furnace_core": 2.0, "fenn_jury_reactor": 2.0}
	for id in want:
		var d := _rig(id)
		var mk1 := float(d["ship"].components.def("reactor_mk1")["power"])
		near(_supply(d["ship"]) - mk1, mk1 + want[id], id + ": its own output", 1e-6)
		near(float(d["ship"].components.def(id)["power"]) - mk1, want[id], id + ": over the Reactor Mk1's output", 1e-6)


func test_the_nest_reactor_is_worth_one_power_for_each_kett_in_its_room_up_to_three() -> void:
	var d := _rig("kett_nest_reactor")
	var ship: Ship = d["ship"]
	var mk1 := float(ship.components.def("reactor_mk1")["power"])
	var own := float(ship.components.def("kett_nest_reactor")["power"])
	check(own < mk1 and own + 3.0 > mk1, "the nest reactor starts below a Reactor Mk1 and ends above it")
	near(_supply(ship) - mk1, own, "nobody home: its own figure, less than a Reactor Mk1")
	_crew(ship, "Ada", "human", 12, 14)
	near(_supply(ship) - mk1, own, "a human is not a Kett")
	_crew(ship, "K1", "kett", 12, 12)
	near(_supply(ship) - mk1, own + 1.0, "one Kett: +1")
	_crew(ship, "K2", "kett", 14, 14)
	var k3 := _crew(ship, "K3", "kett", 16, 14)
	near(_supply(ship) - mk1, own + 3.0, "three Kett: +3, more than a Mk1")
	_crew(ship, "K4", "kett", 18, 14)
	near(_supply(ship) - mk1, own + 3.0, "a fourth adds nothing")
	k3.pos = Pathfinder.centre_of(Vector2i(12, 22))
	near(_supply(ship) - mk1, own + 3.0, "one in the other room leaves three in the room")
	_crew(ship, "K5", "kett", 12, 22).pos = Pathfinder.centre_of(Vector2i(14, 22))
	near(_supply(ship) - mk1, own + 3.0, "and those in the other room never count")
	ship.crew[2].pos = Pathfinder.centre_of(Vector2i(12, 22))  # K1 walks off too
	near(_supply(ship) - mk1, own + 2.0, "two left in the room (K2, K4) and a human: +2")


func test_the_forge_vents_the_room_and_only_a_human_suffers() -> void:
	var hp := {}
	for species in ["human", "basalt"]:
		var d := _rig("basalt_vacuum_forge")
		var ship: Ship = d["ship"]
		var m := _crew(ship, "Wren", species, 12, 14)
		_run(ship, 120.0)
		check(ship.atmosphere.pressure_at(m.cell()) < 0.05, "%s: the room is vented" % species)
		hp[species] = m.hp
	check(hp["human"] < 60.0, "a human suffocates in the forge room: %s" % hp["human"])
	near(hp["basalt"], 140.0, "a Basalt loses nothing", 1e-6)


func test_the_furnace_core_runs_hot_and_trips_without_a_radiator_for_any_crew() -> void:
	var tripped := {}
	for species in ["human", "emberkin"]:
		var d := _rig("emberkin_furnace_core")
		var ship: Ship = d["ship"]
		_crew(ship, "Wren", species, 12, 14)
		check(not _run(ship, 60.0, true), species + ": it has not tripped after a minute")
		near(float(ship.components.instances[d["part"]]["heat"]), 54.0, species + ": 0.9 a second beyond what it sheds, a minute in", 1.5)
		tripped[species] = _run(ship, 90.0, true)
	eq(tripped, {"human": true, "emberkin": true}, "it overheats whoever is aboard: heat is cancelled by nobody")
	var d := _rig("emberkin_furnace_core")
	Fixture.put(d["ship"], "radiator", 19, 10)
	Fixture.wire(d["ship"], [Vector2i(16, 11), Vector2i(17, 11), Vector2i(18, 11), Vector2i(19, 11)])  # from the 2 wide core (x 15..16) to the radiator
	d["ship"].refresh()
	check(not _run(d["ship"], 300.0, true), "a radiator in the room keeps it from ever tripping")


func test_the_jury_reactor_and_the_haggle_engine_malfunction_at_their_rates() -> void:
	var ship := Fixture.room_ship()
	near(ship.effective("fenn_jury_reactor")["malfunction_per_min"], 0.15, "Jury Reactor 15 percent a minute")
	near(ship.effective("fenn_haggle_engine")["malfunction_per_min"], 0.2, "Haggle Engine 20 percent a minute")
	near(ship.effective("fenn_twitch_cannon")["malfunction_per_min"], 0.2, "Twitch Cannon 20 percent a minute")
	near(ship.effective("engine_mk2")["malfunction_per_min"], 0.01, "against a Mk2's 1 percent")


func test_a_fenn_mends_the_unreliable_parts_in_six_tenths_of_the_time_a_human_takes() -> void:
	var seconds := {}
	for species in ["human", "fenn"]:
		var d := _rig("fenn_jury_reactor")
		var ship: Ship = d["ship"]
		ship.components.instances[d["part"]]["status"] = "malfunction"
		var m := _crew(ship, "Wren", species, 12, 14)
		var jobs := Jobs.new()
		var job := jobs._fix_job(ship, d["part"])
		var t := 0.0
		while _status(d) != "ok" and t < 30.0:
			jobs.work(ship, m, job, 0.1)
			t += 0.1
		seconds[species] = t
	var part := float(Jobs.jcfg()["repair_component"]["seconds"])  # data/crew.json: 12 s
	near(seconds["human"], part, "a human mends it in the job's time", 0.15)
	near(seconds["fenn"], part * 0.6, "a Fenn in 0.6 of it", 0.15)


func test_the_hot_parts_scorch_a_mixed_crew_and_an_emberkin_crew_runs_them_free() -> void:
	var rates := {"emberkin_pyre_drive": 1.6, "emberkin_furnace_core": 1.2, "emberkin_hearth_shield": 0.5}
	for id in rates:
		var d := _rig(id)
		var ship: Ship = d["ship"]
		var human := _crew(ship, "Ada", "human", 12, 14)
		var ember := _crew(ship, "Tess", "emberkin", 14, 14)
		var away := _crew(ship, "Away", "human", 12, 22)
		_run(ship, 10.0)
		near(human.max_hp - human.hp, rates[id] * 10.0, id + ": a human in its room loses its scorch rate", 0.2)
		near(ember.hp, ember.max_hp, id + ": an Emberkin loses nothing", 1e-6)
		near(away.hp, away.max_hp, id + ": nor does anyone in another room", 1e-6)


# --- engines -----------------------------------------------------------------------------------------------------

func test_the_pyre_drive_pushes_27_and_heats_itself_until_it_trips() -> void:
	var d := _rig("emberkin_pyre_drive")
	var ship: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(ship)
	near(a.ships[0].thrust, 27.0, "thrust 27, x1.5 over a Mk2's 18")
	check(not _run(ship, 60.0, true), "it has not tripped after a minute")
	near(float(ship.components.instances[d["part"]]["heat"]), 72.0, "1.2 a second beyond what it sheds, a minute in", 2.0)
	check(_run(ship, 60.0, true), "and it trips in the second minute without a radiator")


func test_the_haggle_engine_pushes_23() -> void:
	var d := _rig("fenn_haggle_engine")
	var a := Arena.new(1)
	a.add_ship(d["ship"])
	near(a.ships[0].thrust, 23.0, "thrust 23, x1.3 over a Mk2's 18")


# --- shields -----------------------------------------------------------------------------------------------------

func test_the_hearth_shield_gives_a_third_layer_while_the_room_is_hot() -> void:
	var d := _rig("emberkin_hearth_shield")
	var ship: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(ship)
	eq(a.ships[0].layers_cap, 2, "cool: two layers, like a Mk2")
	ship.components.instances[d["reactor"]]["heat"] = 70.0  # any part of the room counts: a Furnace Core beside it
	a.step(0.05)
	eq([a.ships[0].layers_cap, a.ships[0].layers], [3, 6], "a hot room: three layers (a Mk2's two sectors hold them twice)")
	ship.components.instances[d["reactor"]]["heat"] = 20.0
	a.step(0.05)
	eq(a.ships[0].layers_cap, 2, "cooled: two again")
	_run(ship, 60.0, true)
	near(float(ship.components.instances[d["part"]]["heat"]), 48.0, "and it warms itself 0.8 a second beyond what it sheds, a minute in", 1.5)


func test_the_hive_battery_blooms_with_three_crew_and_sulks_with_fewer() -> void:
	var d := _rig("kett_hive_battery")
	var ship: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(ship)
	eq(a.ships[0].layers_cap, 1, "nobody there: 3 x 0.5 rounds down to one layer")
	_crew(ship, "K1", "kett", 12, 14)
	_crew(ship, "K2", "kett", 14, 14)
	a.step(0.05)
	eq(a.ships[0].layers_cap, 1, "two: still one")
	var k3 := _crew(ship, "K3", "kett", 16, 14)
	a.step(0.05)
	eq([a.ships[0].layers_cap, a.ships[0].layers], [3, 6], "three: all three layers (two sectors), up at once")
	k3.pos = Pathfinder.centre_of(Vector2i(12, 22))
	a.step(0.05)
	eq(a.ships[0].layers_cap, 1, "one walks off: back to one")


# --- utility -----------------------------------------------------------------------------------------------------

func test_the_comms_array_names_what_it_sees_within_2400_px() -> void:
	var d := _rig("human_comms_array")
	var r := Radar.ranges(d["ship"])
	near(float(r["identify_range"]), 2400.0, "a radar that names contacts within 2400 px")
	near(float(r["range"]), 2400.0, "and sees as far (no helm here: its own radar is the only one)")
	var plain := Fixture.room_ship()
	near(float(Radar.ranges(plain)["identify_range"]), 0.0, "a ship without it names nothing")


func test_the_crew_quarters_heal_twice_a_bed_and_speed_the_crew_up_five_percent() -> void:
	var d := _rig("human_crew_quarters_deluxe")
	var ship: Ship = d["ship"]
	var bed := Fixture.put(ship, "bed", 12, 19, 1)
	check(bed >= 0, "(setup: a plain bed in the other room)")
	ship.refresh()
	var pod := _crew(ship, "Pod", "human", 15, 10)
	var rest := _crew(ship, "Bunk", "human", 12, 19)
	var jobs := Jobs.new()
	var pod_rate := jobs._heal_rate(ship, pod)
	var bed_rate := jobs._heal_rate(ship, rest)
	near(pod_rate, 10.0, "a powered pod heals 10 hp a second", 0.1)
	near(bed_rate, 5.0, "a bed 5")
	near(pod_rate / bed_rate, 2.0, "twice a bed", 0.05)
	near(Jobs._work_rate(ship, pod, "repair_component"), 1.05, "crew in its room work 5 percent faster")
	near(Jobs._work_rate(ship, rest, "repair_component"), 1.0, "crew elsewhere do not")
	ship.components.instances[d["part"]]["status"] = "disabled"
	near(jobs._heal_rate(ship, pod), 0.0, "an unpowered pod heals nobody: it draws 1 power")


func test_the_quickfix_bay_doubles_the_work_in_its_room_and_stacks_with_quick_hands() -> void:
	var d := _rig("fenn_quickfix_bay")
	var ship: Ship = d["ship"]
	var human := _crew(ship, "H", "human", 12, 14)
	var fenn := _crew(ship, "F", "fenn", 14, 14)
	var away := _crew(ship, "A", "human", 12, 22)
	for kind in ["repair_component", "extinguish", "repair_breach", "revive"]:
		near(Jobs._work_rate(ship, human, kind), 2.0, "a human on %s: x2" % kind)
		near(Jobs._work_rate(ship, away, kind), 1.0, "someone elsewhere on %s: x1" % kind)
	near(Jobs._work_rate(ship, fenn, "repair_component"), 2.0 / 0.6, "a Fenn's quick hands on top", 1e-3)


func test_the_brood_hold_speeds_the_kett_and_slows_the_rest() -> void:
	var d := _rig("kett_brood_hold")
	var ship: Ship = d["ship"]
	var kett := _crew(ship, "K", "kett", 12, 14)
	var human := _crew(ship, "H", "human", 14, 14)
	var away := _crew(ship, "A", "kett", 12, 22)
	for kind in ["repair_component", "extinguish", "repair_breach", "revive"]:
		near(Jobs._work_rate(ship, kett, kind), 1.2, "a Kett on %s: x1.2" % kind)
		near(Jobs._work_rate(ship, human, kind), 0.8, "a human on %s: x0.8" % kind)
		near(Jobs._work_rate(ship, away, kind), 1.0, "a Kett in the other room on %s: x1" % kind)


func test_the_stonehide_bay_thickens_the_walls_and_the_room_loses_its_air() -> void:
	var d := _rig("basalt_stonehide_bay")
	var ship: Ship = d["ship"]
	near(ship.grid.hp_of(Vector2i(8, 12)), 4.0, "a wall is 4 hp before the fight")
	var a := Arena.new(1)
	a.add_ship(ship)
	near(ship.grid.hp_of(Vector2i(8, 12)), 6.0, "x1.5 once a fight starts")
	near(ship.grid.hp_of(Vector2i(8, 22)), 4.0, "the other room's walls are as they were")
	var hp := {}
	for species in ["human", "basalt"]:
		var e := _rig("basalt_stonehide_bay")
		var m := _crew(e["ship"], "Wren", species, 12, 14)
		_run(e["ship"], 240.0)
		check(e["ship"].atmosphere.pressure_at(m.cell()) < 0.3, "%s: the room cannot keep its air" % species)
		hp[species] = m.hp
	check(hp["human"] < 100.0, "a human suffers in a bay room: %s" % hp["human"])
	near(hp["basalt"], 140.0, "a Basalt does not", 1e-6)


func test_the_gravity_anchor_takes_the_sting_out_of_a_ram_and_pulls_the_room_air() -> void:
	var d := _rig("basalt_gravity_anchor")
	var ship: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(ship)
	var damp: Dictionary = Collisions._dampener(a, 0)
	near(float(damp["take"]), 0.35, "ram damage to the plain cells x0.35")
	eq(damp["no_knock"], true, "and the crew keep their feet")
	var m := _crew(ship, "Wren", "basalt", 12, 14)
	_run(ship, 120.0)
	check(ship.atmosphere.pressure_at(m.cell()) < 0.1, "but it pulls the air out of its room")
	near(m.hp, 140.0, "which a Basalt does not mind", 1e-6)
	var lone := Arena.new(1)
	lone.add_ship(Fixture.room_ship())
	near(float(Collisions._dampener(lone, 0)["take"]), 1.0, "a ship without it takes a ram in full")


# --- the cons the traits cancel, in one place -------------------------------------------------------------------

func test_the_traits_that_cancel_the_cons() -> void:
	var basalt := TraitSet.of(CrewMember.new("B", Vector2.ZERO, "basalt"))
	var fenn := TraitSet.of(CrewMember.new("F", Vector2.ZERO, "fenn"))
	var ember := TraitSet.of(CrewMember.new("E", Vector2.ZERO, "emberkin"))
	var kett := TraitSet.of(CrewMember.new("K", Vector2.ZERO, "kett"))
	near(float(basalt["o2_use"]), 0.0, "Basalt breathe nothing: the forge, the bay and the anchor cost them none")
	near(float(fenn["work_mult"]["repair"]), 1.0 / 0.6, "Fenn repair x1/0.6: the Jury Reactor, Haggle Engine, Twitch Cannon and Spark Lattice cost them little", 1e-3)
	near(float(ember["damage_taken"]["fire"]), 0.25, "Emberkin take a quarter of the burn when a hot part trips and starts a fire")
	check(PartEffects.matches(CrewMember.new("K", Vector2.ZERO, "kett"), "kett"), "a Kett is what the nest and the brood name")
	check(not kett.is_empty(), "(the Kett have traits)")
