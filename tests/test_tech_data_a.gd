extends "res://tests/base_test.gd"
## Racial tech, group a: Human, Basalt, Emberkin, Fenn and Kett (docs/waves/racial_tech_1.md, docs/CONTENT.md section 17).
## Their packs are data/packs/tech_<race>/. Here: each part is what the spec says (shape, tier, pro, con), its recipe is
## sane, and each weapon does what its data claims when it is really fired in the arena (the generic effect code is
## tested in test_fx_effects.gd; this proves the data reaches it).

const Arena = preload("res://scripts/combat/arena.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Content = preload("res://scripts/data/content.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")

const RACES: Array[String] = ["human", "basalt", "emberkin", "fenn", "kett"]
const KEY_MATERIALS: Array[String] = ["military_circuit", "gate_alloy", "void_crystal", "nanite_paste"]
const HOMELAND := {"human": "human_core", "basalt": "basalt_quarries", "emberkin": "emberkin_forges", "fenn": "fenn_bazaar", "kett": "kett_hives"}
## weapon id -> [tier, turret, kind, damage_type, power]
const WEAPONS := {
	"human_volley_rack": [2, false, "missile", "explosive", -3], "human_concord_railgun": [3, false, "bolt", "kinetic", -5],
	"human_flak_screen": [2, true, "flak", "kinetic", -4],
	"basalt_magma_spitter": [2, false, "bolt", "kinetic", -3], "basalt_quarry_driver": [3, false, "bolt", "kinetic", -4],
	"basalt_pumice_flak": [2, true, "flak", "kinetic", -4],
	"emberkin_pyre_lance": [2, false, "beam", "energy", -4], "emberkin_cinder_mortar": [2, false, "bolt", "explosive", -3],
	"emberkin_flare_turret": [1, true, "bolt", "energy", -3],
	"fenn_twitch_cannon": [2, true, "bolt", "energy", -3], "fenn_spark_lattice": [2, true, "bolt", "energy", -4],
	"fenn_market_missile": [2, false, "missile", "explosive", -3],
	"kett_hive_swarm_launcher": [2, false, "missile", "explosive", -3], "kett_chitin_thrower": [1, false, "flak", "kinetic", -2],
	"kett_drone_picket": [2, true, "bolt", "kinetic", -4],
}

var arena: Arena
var gun: int
var target: Ship


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _species_ids() -> Array:
	var out := []
	for s in Content.list("species"):
		out.append(s["id"])
	return out


## Damage a second of a weapon entry as the data states it: damage x shots / cooldown (a turret deals its share).
func _dps(w: Dictionary) -> float:
	var held := float(w["duration"]) if w["kind"] == "beam" else float(w["shots"])  # a beam's damage is per second
	return float(w["damage"]) * held / float(w["cooldown"])


# --- the packs ----------------------------------------------------------------------------------------------

func test_the_five_packs_load_with_no_problems_and_say_where_they_are_sold() -> void:
	var have := {}
	for p in Content.packs():
		have[p["id"]] = p
	for r in RACES:
		var id := "tech_" + r
		check(have.has(id), id + " is a pack")
		if have.has(id):
			check(str(have[id]["notes"]).contains(HOMELAND[r]), id + ": the notes say which region sells it")
	eq(Content.errors(), [], "the content loads with no errors")


func test_the_homeland_stores_sell_the_weapons() -> void:
	for id in WEAPONS:
		var race: String = id.split("_")[0]
		var region = JSON.parse_string(FileAccess.get_file_as_string("res://data/regions/%s.json" % HOMELAND[race]))
		eq(region["home_species"], race, HOMELAND[race] + " is the home of the " + race)
		check(region["stock"].has(id) and float(region["stock"][id]) > 0.0, "%s is in the stock of %s" % [id, HOMELAND[race]])


func test_each_race_has_its_three_ship_weapons() -> void:
	var per := {}
	for id in WEAPONS:
		var race: String = id.split("_")[0]
		per[race] = int(per.get(race, 0)) + 1
		eq(Content.origin("components", id), "tech_" + race, id + ": comes from the race's pack")
		eq(Content.origin("weapons", id), "tech_" + race, id + ": its weapons entry too")
		eq(Content.origin("recipes", id), "tech_" + race, id + ": and its recipe")
	for r in RACES:
		eq(per.get(r, 0), 3, r + ": three ship weapons")


func test_every_weapon_is_the_shape_the_spec_gives() -> void:
	var w := Weapons.new()
	var species := _species_ids()
	for id in WEAPONS:
		var want: Array = WEAPONS[id]
		var c := Content.entry("components", id)
		eq([int(c["tier"]), c["family"], c["line"], int(c["power"]), int(c["priority"]), c["manned"]], [want[0], "weapon", "standard", want[4], 5, true], id + ": tier, family, line, power, priority, manned")
		eq([int(c["size"][0]), int(c["size"][1])], [2 if int(want[0]) <= 2 else 4, 2], id + ": a hull mount with a 4x2 inside half (2x2 for tier 1-2, playtest 2 P2)")
		eq([int(c["mount"]["outside"][0]), int(c["mount"]["outside"][1])], w.shapes[c["shape"]]["outside"], id + ": and the outside half of its shape (docs/GUNS.md 3)")
		check(float(c["mount"]["outside_hp"]) >= 4.0, id + ": the outside half has hp")
		check(str(c.get("blurb", "")).length() > 20 and str(c.get("quirk", "")).length() > 20, id + ": a blurb and a quirk line")
		check(not c.get("unique", false), id + " is not unique")
		var e: Dictionary = w.defs[id]
		eq([e["kind"], e["damage_type"], bool(e["turret"])], [want[2], want[3], want[1]], id + ": kind, damage type, turret")
		eq(Effects.problems(e, species), [], id + ": its effects pass the validator")
		if want[1]:
			check(float(e["accuracy"]) >= 0.6 and float(e["accuracy"]) <= 0.85, id + ": turret accuracy 0.6 to 0.85")


func test_the_recipes_are_fab_level_two_and_tier_three_needs_a_key_material() -> void:
	for id in WEAPONS:
		var r := Content.entry("recipes", id)
		eq([r["output"]["item"], int(r["output"]["count"])], [id, 1], id + ": the recipe makes the part")
		eq(int(r["fab_level"]), 2, id + ": fab level 2")
		var key := false
		for m in r["materials"]:
			key = key or m in KEY_MATERIALS
			check(Content.has("materials", m) or Content.has("items", m), "%s: %s exists" % [id, m])
		eq(key, WEAPONS[id][0] == 3, id + ": a key material exactly when it is tier 3")


# --- the numbers: a pro of 30 to 55 percent over the family it comes from ---------------------------------------------

func test_the_damage_a_second_is_30_to_55_percent_over_the_family_part_it_replaces() -> void:
	var w := Weapons.new()
	var pulse := _dps(w.def("pulse_mk2"))
	var turret_pulse := 0.6 * pulse
	var artemis := _dps(w.def("artemis_mk1"))
	var heat_lance := _dps(w.def("heat_lance_neon"))
	var acid: Dictionary = w.defs["basalt_magma_spitter"]["effects"]["acid"]
	var spitter: Dictionary = w.def("basalt_magma_spitter")
	var lattice: Dictionary = w.def("fenn_spark_lattice")
	var splinters: Dictionary = w.defs["fenn_spark_lattice"]["effects"]["shard"]
	var table := {
		"human_volley_rack": [_dps(w.def("human_volley_rack")) / artemis, "against the Artemis"],
		"basalt_magma_spitter": [(float(spitter["damage"]) + float(acid["dps"]) * float(acid["seconds"])) / float(spitter["cooldown"]) / pulse, "hit plus acid against Pulse Mk2"],
		"emberkin_pyre_lance": [_dps(w.def("emberkin_pyre_lance")) / heat_lance, "against the Heat Lance"],
		"fenn_spark_lattice": [(_dps(lattice) + float(splinters["splinters"]) * float(splinters["dmg"]) / float(lattice["cooldown"])) / turret_pulse, "hit plus splinters against a Pulse Mk2 turret"],
		"kett_hive_swarm_launcher": [_dps(w.def("kett_hive_swarm_launcher")) / artemis, "against the Artemis"],
	}
	for id in table:
		var ratio: float = table[id][0]
		check(ratio >= 1.3 - 1e-6 and ratio <= 1.55 + 1e-6, "%s: %.2f times %s (want 1.30 to 1.55)" % [id, ratio, table[id][1]])


# --- firing them for real ---------------------------------------------------------------------------------------

## Ship 0 is a sealed-room ship with the mount `id` inside the room at (12.5, 15.5), loaded with ammo; ship 1 is the same
## ship `dist` px away. A shot along the world row y = 0 hits the wall at (8, 15) of the target.
func _duel(id: String, dist := 600.0, seed_value := 1) -> Ship:
	var shooter := Fixture.room_ship()
	shooter.inventory.load_dict({"scrap": 200, "missile": 50})
	arena = Arena.new(seed_value)
	arena.add_ship(shooter)
	target = Fixture.room_ship()
	arena.add_ship(target, Vector2(dist, 0.0))
	gun = arena.add_mount(0, id, Vector2(12.5, 15.5), true, Vector2.RIGHT)  # on row 15, aimed east at the target's wall
	return shooter


func _shoot() -> bool:
	arena.ships[0].cooldowns.clear()
	return arena.fire(0, gun, arena.cell_to_world(1, Vector2i(8, 15)))


func _events(kind: String) -> Array:
	return arena.events.filter(func(e): return e["type"] == "effect" and e["kind"] == kind)


func _person(name: String, species: String, x: float, y: float) -> CrewMember:
	return CrewMember.new(name, Vector2(x, y), species)


func _cooldown_with(id: String, species: String, n: int) -> float:
	var shooter := _duel(id)
	for i in n:
		shooter.crew.append(_person("C%d" % i, species, 12.5 + i, 14.5))
	_shoot()
	return arena.cooldown_left(0, gun)


func test_volley_rack_launches_three_missiles_and_spends_one_and_a_half() -> void:
	var shooter := _duel("human_volley_rack")
	var spent := []
	for i in 4:
		var before := shooter.inventory.count("missile")
		var p := arena.projectiles.size()
		check(_shoot(), "fires")
		eq(arena.projectiles.size() - p, 3, "three missiles a salvo")
		spent.append(before - shooter.inventory.count("missile"))
	eq(spent, [1, 2, 1, 2], "ammo x1.5: one, two, one, two")


func test_concord_railgun_is_a_fast_piercing_slug_that_charges_slowly() -> void:
	var w := Weapons.new()
	var rail := w.def("human_concord_railgun")
	eq(int(rail["pierce"]), 2, "pierces 2")
	check(float(rail["speed"]) >= 2.0 * float(w.def("pulse_mk2")["speed"]), "at more than twice a pulse's speed")
	near(float(rail["cooldown"]) / (1.3 * 1.75), 1.5, "charge 1.5 times the 2.3 s (1.3 x 1.75) of a tier-3 bolt", 0.06)
	_duel("human_concord_railgun")
	_shoot()
	arena.step(1.0)
	check(target.grid.hp_of(Vector2i(8, 15)) <= 0.0, "and it goes through a steel wall")


func test_flak_screen_is_a_quick_accurate_turret_with_weak_pellets() -> void:
	var w := Weapons.new()
	var flak := w.def("human_flak_screen")
	check(float(flak["damage"]) < float(w.def("shrapnel_cannon_scrap")["damage"]), "each pellet is weaker than a Shrapnel Cannon's")
	check(float(flak["cooldown"]) < 2.5 and float(flak["accuracy"]) >= 0.85, "but it fires fast (the quickest flak: 2.1 s) and true")


func test_magma_spitter_starts_an_acid_and_vents_thirty_percent_of_its_room() -> void:
	var shooter := _duel("basalt_magma_spitter")
	near(shooter.atmosphere.pressure_at(Vector2i(12, 12)), 1.0, "(a full room)")
	_shoot()
	near(shooter.atmosphere.pressure_at(Vector2i(12, 12)), 0.7, "30 percent of the air gone with the shot")
	arena.step(2.0)
	check(not _events("acid").is_empty(), "and the slag burns on where it landed")


func test_a_basalt_does_not_mind_the_vented_room_and_a_human_does() -> void:
	var shooter := _duel("basalt_magma_spitter")
	var rock := _person("Rock", "basalt", 14.5, 13.5)
	var human := _person("Ada", "human", 17.5, 13.5)
	shooter.crew.append_array([rock, human])
	for i in 6:
		_shoot()
		arena.step(1.0)
	check(shooter.atmosphere.pressure_at(Vector2i(12, 12)) < 0.3, "six shots empty the room")
	var sim := ShipSim.new()
	sim.ships = [shooter]
	for i in 30:
		sim._step_ship(shooter, 1.0)
	near(rock.hp, rock.max_hp, "the Basalt lost nothing", 1e-6)
	check(human.hp < human.max_hp, "the human is suffocating")


func test_quarry_driver_is_a_huge_slug_that_pierces_three_and_vents_forty_percent() -> void:
	var w := Weapons.new()
	var q := w.def("basalt_quarry_driver")
	eq(int(q["pierce"]), 3, "pierces 3")
	check(float(q["damage"]) >= 2.0 * float(w.def("pulse_mk2")["damage"]), "at least double a Pulse Mk2's hit")
	var shooter := _duel("basalt_quarry_driver")
	_shoot()
	near(shooter.atmosphere.pressure_at(Vector2i(12, 12)), 0.6, "40 percent of the room's air goes with the shot")
	arena.step(2.0)
	check(target.grid.hp_of(Vector2i(8, 15)) <= 0.0, "and the wall is gone")


func test_pumice_flak_halves_its_damage_unless_a_basalt_mans_it() -> void:
	var dealt := []
	for who in ["", "Ada", "Rock"]:
		var shooter := _duel("basalt_pumice_flak")
		shooter.crew.append_array([_person("Ada", "human", 14.5, 12.5), _person("Rock", "basalt", 15.5, 12.5)])
		if who != "":
			shooter.manned[gun] = who
		var m: Dictionary = arena.ships[0].mounts[gun]
		dealt.append(float(Effects.adjust(arena, 0, gun, m, arena.weapons.def("basalt_pumice_flak"))["damage"]))
	near(dealt[0], dealt[2] * 0.5, "nobody at it: half", 1e-6)
	near(dealt[1], dealt[2] * 0.5, "a human at it: half", 1e-6)
	check(float(arena.weapons.defs["basalt_pumice_flak"]["splash"]) > 0.0, "and it splashes")


func test_pyre_lance_sweeps_a_burning_beam_and_heats_its_room_by_forty() -> void:
	var shooter := _duel("emberkin_pyre_lance")
	var reactor := Fixture.put(shooter, "reactor_mk1", 12, 10)
	check(reactor >= 0, "(setup)")
	shooter.refresh()
	_shoot()
	near(float(shooter.components.instances[reactor]["heat"]), 40.0, "40 heat to the parts in its room")
	eq(arena.beams.size(), 1, "a beam is burning")
	near(float(arena.weapons.def("emberkin_pyre_lance")["fire_chance"]), 0.4, "lighting fires at 40 percent a tick")


func test_cinder_mortar_sometimes_burns_its_own_room() -> void:
	var w := Weapons.new()
	near(float(w.defs["emberkin_cinder_mortar"]["effects"]["self_room"]["fire_chance"]), 0.15, "15 percent a shot in its own room")
	_duel("emberkin_cinder_mortar", 600.0, 3)
	var n := 0
	for i in 40:
		_shoot()
		n = arena.events.filter(func(e): return e["type"] == "ignite" and e["ship"] == 0).size()
	check(n >= 1 and n <= 14, "40 shots light its room a few times (%d), not never and not always" % n)
	check(float(w.def("emberkin_cinder_mortar")["splash"]) >= 2.0 and float(w.def("emberkin_cinder_mortar")["fire_chance"]) > 0.3, "and the shell splashes and lights the target")


func test_flare_turret_stuns_the_crew_in_the_room_it_hits_and_runs_hot() -> void:
	_duel("emberkin_flare_turret")
	var ada := _person("Ada", "human", 14.5, 12.5)
	target.crew.append(ada)
	var stunned := false
	for i in 400:
		arena.step(0.05)
		stunned = stunned or ada.stun > 0.0
	check(stunned, "the human in the room hit was stunned")
	var w := Weapons.new()
	check(float(w.def("emberkin_flare_turret")["heat_per_shot"]) >= 25.0, "each flare adds a lot of heat to the turret")


func test_twitch_cannon_is_a_rapid_turret() -> void:
	_duel("fenn_twitch_cannon")
	_shoot()
	near(arena.cooldown_left(0, gun), 0.6, "a shot every 0.6 s", 0.02)
	var w := Weapons.new()
	check(bool(w.defs["fenn_twitch_cannon"].get("rapid", false)) and bool(w.def("fenn_twitch_cannon")["turret"]), "one of the few rapid guns, so a turret")
	check(float(w.def("fenn_twitch_cannon")["cooldown"]) < 0.5 * float(w.def("pulse_mk2")["cooldown"]), "far quicker than Pulse Mk2")


func test_spark_lattice_throws_splinters_beside_each_hit() -> void:
	_duel("fenn_spark_lattice")
	for i in 400:
		arena.step(0.05)
	check(not _events("shard").is_empty(), "a hit threw splinters")
	eq(arena.weapons.defs["fenn_spark_lattice"]["effects"]["shard"]["splinters"], 3, "three of them")


func test_market_missile_fires_scrap() -> void:
	var shooter := _duel("fenn_market_missile")
	var before := shooter.inventory.count("scrap")
	_shoot()
	eq(before - shooter.inventory.count("scrap"), 1, "one scrap a missile")
	check(arena.weapons.def("fenn_market_missile")["pass_shields"], "it passes shields like any missile")
	check(float(arena.weapons.def("fenn_market_missile")["damage"]) < 4.0, "its damage already counts the duds (4 x 0.75 = 3)")


func test_hive_swarm_launcher_wants_three_crew_in_its_room() -> void:
	var cd := []
	for n in [1, 2, 3]:
		cd.append(_cooldown_with("kett_hive_swarm_launcher", "kett", n))
	var base := float(Weapons.new().def("kett_hive_swarm_launcher")["cooldown"])
	near(cd[0], base / 0.4, "alone: x0.4 rate", 0.05)
	near(cd[1], base / 0.4, "two: still short", 0.05)
	near(cd[2], base, "three: full rate", 0.05)
	var shooter := _duel("kett_hive_swarm_launcher")
	_shoot()
	eq(arena.projectiles.size(), 6, "six tiny drones a salvo")


func test_chitin_thrower_wants_two_and_splinters() -> void:
	var cd := []
	for n in [1, 2]:
		cd.append(_cooldown_with("kett_chitin_thrower", "kett", n))
	var base := float(Weapons.new().def("kett_chitin_thrower")["cooldown"])
	near(cd[0], 2.0 * base, "alone: half rate", 0.05)
	near(cd[1], base, "two: full rate", 0.05)
	_duel("kett_chitin_thrower", 300.0)
	_shoot()
	arena.step(1.5)
	check(not _events("shard").is_empty(), "the needles splinter into the next cell")


func test_drone_picket_wants_two_crew_nearby() -> void:
	var cd := []
	for n in [1, 2]:
		cd.append(_cooldown_with("kett_drone_picket", "kett", n))
	near(cd[0], 1.0, "alone: half rate", 0.05)
	near(cd[1], 0.5, "two: full rate", 0.05)
	eq(int(Weapons.new().def("kett_drone_picket")["shots"]), 1, "a drone a shot, every 0.5 s (a rapid turret)")


# --- the Kett hand weapons ----------------------------------------------------------------------------------------

func test_kett_hand_weapons_follow_the_class_figures_within_twenty_percent() -> void:
	var classes := {"pistol": [10.0, 1.5, 300.0], "melee": [25.0, 1.2, 40.0]}
	var found := {}
	for h in Content.list("hand_weapons"):
		if h.get("culture", "") != "kett":
			continue
		found[h["id"]] = h["class"]
		var base: Array = classes[h["class"]]
		for i in 3:
			var got := float(h[["damage", "rate", "range"][i]])
			check(got >= base[i] * 0.8 - 1e-6 and got <= base[i] * 1.2 + 1e-6, "%s: %s within 20 percent of the %s figure" % [h["id"], ["damage", "rate", "range"][i], h["class"]])
		check(str(h["notes"]).contains("%"), h["id"] + ": a shifted figure says by how much")
		eq(Content.origin("hand_weapons", h["id"]), "tech_kett", h["id"] + ": from the Kett pack")
	eq(found, {"sting_pistol": "pistol", "hive_prod": "melee"}, "a pistol and a melee weapon")
