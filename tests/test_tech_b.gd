extends "res://tests/base_test.gd"
## Racial tech, group b (docs/waves/racial_tech_1.md): the arsenals of the Mire, Sporeling, Gauntling, Prismatic and
## Grundl, five packs (data/packs/tech_<race>) of 3 ship weapons, 3 components and 2 hand weapons each. The numbers
## against the parts they replace, every weapon fired through the arena and leaving its mark, each con meeting the
## trait of its own race (and costing a mixed crew), the recipes, the homeland stores and the hand weapons.

const Abilities = preload("res://scripts/sim/abilities.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Components = preload("res://scripts/ship/components.gd")
const Content = preload("res://scripts/data/content.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Stats = preload("res://scripts/sim/stats.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")

const DT := 1.0 / 60.0
## race -> [weapons, components, hand weapons]
const RACES := {
	"mire": [["mire_steam_lance", "mire_bog_mortar", "mire_mist_projector"], ["mire_rain_shield", "mire_wetwell_reactor", "mire_spray_deck"], ["bubble_rifle", "hook_gaff"]],
	"sporeling": [["sporeling_spore_cannon", "sporeling_rot_pod", "sporeling_pollen_turret"], ["sporeling_bloom_reactor", "sporeling_mycelium_shield", "sporeling_garden_bay"], ["spore_puffer", "thorn_lash"]],
	"gauntling": [["gauntling_arc_hammer", "gauntling_scrap_shotgun", "gauntling_tesla_picket"], ["gauntling_arc_core", "gauntling_overclock_engine", "gauntling_graft_bay"], ["rivet_fist", "arc_welder"]],
	"prismatic": [["prismatic_prism_lens", "prismatic_refractor", "prismatic_glimmer_turret"], ["prismatic_lattice_shield", "prismatic_song_reactor", "prismatic_resonance_helm"], ["lens_pistol", "shard_lance"]],
	"grundl": [["grundl_slug_mortar", "grundl_grapple_harpoon", "grundl_barge_flak"], ["grundl_hauler_thrusters", "grundl_freight_shield", "grundl_cargo_deck"], ["freight_hammer", "chain_gun"]],
}
## The homeland region of each race (data/regions): its station sells the race's parts.
const HOME := {"mire": "mire_fens", "sporeling": "sporeling_groves", "gauntling": "gauntling_scrapyards", "prismatic": "prismatic_choir", "grundl": "grundl_barges"}
## weapon -> the effect kind its shot leaves on the target (an "effect" arena event), "" when it leaves none
const MARK := {
	"mire_bog_mortar": "corrode", "mire_mist_projector": "frost", "sporeling_spore_cannon": "spores", "sporeling_rot_pod": "acid",
	"sporeling_pollen_turret": "sonic", "gauntling_arc_hammer": "sonic", "gauntling_scrap_shotgun": "shard", "gauntling_tesla_picket": "shard",
	"prismatic_refractor": "shard", "grundl_grapple_harpoon": "magnetic",
}
## weapon -> what it costs its own room per shot (an "effect" self_room event)
const SELF := ["sporeling_spore_cannon", "sporeling_rot_pod", "sporeling_pollen_turret", "gauntling_arc_hammer", "gauntling_tesla_picket"]
const CULTURES := ["mire", "sporeling", "gauntling", "prismatic", "grundl"]
const CLASSES := {"pistol": [10.0, 1.5, 300.0], "rifle": [14.0, 2.0, 500.0], "heavy": [30.0, 0.6, 350.0], "melee": [25.0, 1.2, 40.0], "tool": [6.0, 1.0, 60.0]}

var arena: Arena


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _comps() -> Components:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	return c


func _all(slot: int) -> Array:
	var out := []
	for race in RACES:
		out.append_array(RACES[race][slot])
	return out


func _race_of(id: String) -> String:
	return id.get_slice("_", 0)


# --- the data ----------------------------------------------------------------------------------------

func test_the_thirty_parts_and_ten_hand_weapons_sit_in_five_packs() -> void:
	eq(_all(0).size(), 15, "15 ship weapons")
	eq(_all(1).size(), 15, "15 components")
	eq(_all(2).size(), 10, "10 hand weapons")
	check(Content.errors().is_empty(), "the content loads without problems: " + str(Content.errors()))
	var packs := {}
	for p in Content.packs():
		packs[p["id"]] = p
	for race in RACES:
		check(packs.has("tech_" + race), "the pack tech_%s is there" % race)
		check(packs["tech_" + race]["requires"].has("races_1"), "and needs the races it names")
		for id in _all_of(race, 0) + _all_of(race, 1):
			eq(Content.origin("components", id), "tech_" + race, id + " is in its race's pack")
		for id in _all_of(race, 0):
			eq(Content.origin("weapons", id), "tech_" + race, id + " has its weapon entry there too")
			eq(Content.origin("recipes", id), "tech_" + race, id + " and its recipe")
		for id in _all_of(race, 2):
			eq(Content.origin("hand_weapons", id), "tech_" + race, id + " is that race's hand weapon")
	check(packs["tech_grundl"]["requires"].has("engines_1"), "the Slug Mortar's military circuit comes from engines_1")


func _all_of(race: String, slot: int) -> Array:
	return RACES[race][slot]


func test_every_part_has_a_blurb_a_quirk_and_a_pro_with_a_con() -> void:
	var c := _comps()
	for id in _all(0) + _all(1):
		var d := c.def(id)
		check(str(d.get("blurb", "")).length() > 40, id + ": a blurb in its culture's voice")
		check(str(d.get("quirk", "")).length() > 40, id + ": a quirk that says the pro and the con")
		check(not d.get("unique", false), id + " is not a unique: it is crafted and sold")
		check(d.get("tier", 0) >= 1 and d.get("tier", 0) <= 3, id + ": tier 1 to 3")
	for id in _all(0):
		var d := c.def(id)
		eq([d["family"], d["priority"], d["manned"]], ["weapon", 5, true], id + " is a manned weapon station")
		check(Weapons.new().has(id), id + " has weapon stats")
		check(Effects.of(Weapons.new().defs[id]).size() > 0, id + " carries effects of its own")


func test_every_weapon_has_the_tier_and_aim_of_the_spec() -> void:
	var c := _comps()
	var w := Weapons.new()
	# id -> [tier, kind, turret]
	var table := {
		"mire_steam_lance": [2, "laser", false], "mire_bog_mortar": [2, "bolt", false], "mire_mist_projector": [1, "bolt", true],
		"sporeling_spore_cannon": [2, "bolt", false], "sporeling_rot_pod": [2, "missile", false], "sporeling_pollen_turret": [1, "bolt", true],
		"gauntling_arc_hammer": [2, "bolt", false], "gauntling_scrap_shotgun": [1, "flak", false], "gauntling_tesla_picket": [2, "beam", true],
		"prismatic_prism_lens": [2, "beam", false], "prismatic_refractor": [2, "bolt", false], "prismatic_glimmer_turret": [2, "bolt", true],
		"grundl_slug_mortar": [3, "bolt", false], "grundl_grapple_harpoon": [2, "bolt", false], "grundl_barge_flak": [2, "flak", true],
	}
	eq(table.size(), 15, "the table covers the 15")
	for id in table:
		eq([c.def(id)["tier"], w.defs[id]["kind"], bool(w.defs[id]["turret"])], table[id], id + ": tier, kind, aim")
		eq(c.def(id)["mount"]["outside"], [4, 2], id + ": a 4x2 outside half like the art")
		eq(c.def(id)["mount"]["outside_hp"], 2 * int(c.def(id)["hp"]), id + ": a weapon's outside_hp is twice its hp")
	eq(w.defs["grundl_slug_mortar"]["ammo"], "scrap", "the Slug Mortar fires scrap")
	eq(Effects.of(w.defs["grundl_slug_mortar"])["ammo_mult"], 3, "three a shot")
	eq(Effects.of(w.defs["grundl_barge_flak"])["ammo_mult"], 2, "the Barge Flak spends two")
	near(float(w.defs["gauntling_scrap_shotgun"]["jam_chance"]), 0.15, "the Scrap Shotgun jams 15 percent of the time")
	eq(w.defs["gauntling_scrap_shotgun"]["ammo"], "scrap", "and fires scrap")
	eq(w.defs["sporeling_rot_pod"]["ammo"], "missile", "the Rot Pod spends missiles")


func test_the_pros_are_thirty_to_fifty_percent_over_the_part_they_replace() -> void:
	var w := Weapons.new()
	var laser := float(w.defs["laser_mk2"]["damage"])
	var pulse := float(w.defs["pulse_mk2"]["damage"])
	near(float(w.defs["mire_steam_lance"]["damage"]) / laser, 1.4, "Steam Lance: heavy damage, +40 percent over a Laser Mk2", 0.01)
	near(float(w.defs["gauntling_arc_hammer"]["damage"]) / pulse, 1.33, "Arc Hammer: +33 percent over a Pulse Mk2", 0.01)
	near(float(w.defs["gauntling_arc_hammer"]["damage"]) / float(w.defs["gauntling_arc_hammer"]["cooldown"]) / (pulse / float(w.defs["pulse_mk2"]["cooldown"])), 1.24, "and 24 percent in damage a second, before the stun", 0.02)
	near(float(w.defs["mire_mist_projector"]["effects"]["frost"]["slow"]), 0.4, "Mist Projector: 40 percent slower charging")
	near(float(w.defs["mire_bog_mortar"]["effects"]["corrode"]["resist_mult"]), 0.6, "Bog Mortar: a corroded wall takes 1.67 times the damage")
	near(float(w.defs["prismatic_prism_lens"]["damage"]) * float(w.defs["prismatic_prism_lens"]["duration"]) / (float(w.defs["heat_lance_neon"]["damage"]) * float(w.defs["heat_lance_neon"]["duration"])), 1.67, "Prism Lens: a fuller beam than the Heat Lance", 0.01)
	near(float(w.defs["grundl_slug_mortar"]["damage"]) / 4.5, 1.44, "Slug Mortar: +44 percent over a tier-3 laser (4.5)", 0.01)
	check(float(w.defs["prismatic_glimmer_turret"]["accuracy"]) >= float(w.defs["siren_ion_neon"]["accuracy"]), "Glimmer Turret: the most accurate turret")
	check(float(w.defs["prismatic_glimmer_turret"]["track"]) > float(w.defs["siren_ion_neon"]["track"]), "and the quickest to track")
	var c := _comps()
	eq(int(c.def("mire_rain_shield")["stats"]["layers"]), int(c.def("shield_mk2")["stats"]["layers"]) + 1, "Rain Shield: one layer over a Shield Mk2")
	eq(int(c.def("prismatic_lattice_shield")["stats"]["layers"]), int(c.def("shield_mk2")["stats"]["layers"]) + 2, "Lattice Shield: two layers over it")
	eq(int(c.def("grundl_freight_shield")["stats"]["layers"]), int(c.def("shield_mk2")["stats"]["layers"]) + 2, "Freight Shield: two layers over it")
	near(float(c.def("sporeling_mycelium_shield")["stats"]["recharge"]), 2.0 / 1.5, "Mycelium Shield: layers come back 1.5 times as fast", 0.01)
	var mk1: int = c.def("reactor_mk1")["power"]
	eq(c.def("mire_wetwell_reactor")["power"], mk1 + 2, "Wetwell Reactor: +2 power over a Reactor Mk1")
	eq(c.def("sporeling_bloom_reactor")["power"], mk1 + 3, "Bloom Reactor: +3")
	eq(c.def("gauntling_arc_core")["power"], mk1 + 3, "Arc Core: +3")
	near(float(Stats.effective(c.def("prismatic_song_reactor"), Stats.load_lines())["power"]), mk1 * 1.3, "Song Reactor: the neon line's x1.3 on a Reactor Mk1", 0.01)
	near(float(c.def("gauntling_overclock_engine")["stats"]["thrust"]) / float(c.def("engine_mk2")["stats"]["thrust"]), 1.5, "Overclock Engine: thrust x1.5 over a Thruster Mk2", 0.01)
	near(float(c.def("grundl_hauler_thrusters")["stats"]["thrust"]) / float(c.def("engine_mk2")["stats"]["thrust"]), 1.6, "Hauler Thrusters: x1.6", 0.02)
	near(float(c.def("sporeling_garden_bay")["stats"]["o2_rate"]) / float(c.def("oxygen_gen")["stats"]["o2_rate"]), 2.0, "Garden Bay: twice the air of an Oxygen Generator", 0.001)
	eq(c.def("sporeling_garden_bay")["size"], [2, 2], "in a 2x2")
	eq(int(c.def("grundl_cargo_deck")["stats"]["hold"]), 50, "Cargo Deck: +50 hold (no hold limit reads it yet)")


# --- the recipes ----------------------------------------------------------------------------------------

func test_the_recipes_cost_fab_level_two_and_the_tier_three_part_a_key_material() -> void:
	var neon := ["prismatic_refractor", "prismatic_lattice_shield", "prismatic_song_reactor"]  # the neon line is level 3 with the laser cutter (test_crafting)
	var mats := {}
	for m in Content.list("materials"):
		mats[m["id"]] = m
	for id in _all(0) + _all(1):
		var r := Content.entry("recipes", id)
		check(not r.is_empty(), id + " has a recipe")
		eq([r["output"]["item"], int(r["output"]["count"]), r["category"]], [id, 1, "system"], id + ": makes one system")
		eq(int(r["fab_level"]), 3 if id in neon else 2, id + ": fab level")
		eq(r["tools"], ["laser_cutter"] if id in neon else [], id + ": tools")
		for m in r["materials"]:
			check(mats.has(m) or Content.has("items", m), "%s: %s is a material" % [id, m])
			check(int(r["materials"][m]) > 0, id + ": a positive count")
		var key := false
		for m in r["materials"]:
			key = key or (mats[m]["rarity"] == "very_rare" if mats.has(m) else false)
		eq(key, id == "grundl_slug_mortar", id + ": only the tier-3 part needs a very rare key material")
	eq(Content.entry("recipes", "grundl_slug_mortar")["materials"]["military_circuit"], 1, "a military circuit for the Slug Mortar")
	check(int(Content.entry("recipes", "gauntling_scrap_shotgun")["materials"]["scrap"]) * 2 > _total("gauntling_scrap_shotgun"), "the Scrap Shotgun is mostly scrap")
	check(int(Content.entry("recipes", "sporeling_bloom_reactor")["materials"]["scrap"]) + int(Content.entry("recipes", "sporeling_bloom_reactor")["materials"]["polymer"]) + int(Content.entry("recipes", "sporeling_bloom_reactor")["materials"]["copper"]) < _total("reactor_mk1") + 1, "and the Bloom Reactor is cheap")


func _total(id: String) -> int:
	var t := 0
	var r := Content.entry("recipes", id)
	for m in r["materials"]:
		t += int(r["materials"][m])
	return t


# --- every weapon fired --------------------------------------------------------------------------------

## Ship 0 (floor everywhere) with a virtual mount of the real weapon `id`, ship 1 the sealed room ship at x 800.
func _duel(id: String, seed_value := 1) -> int:
	arena = Arena.new(seed_value)
	arena.add_ship(Fixture.room_ship())
	arena.add_ship(Fixture.room_ship(), Vector2(800.0, 0.0))
	arena.ships[0].ship.inventory.add("missile", 50)
	arena.weapons.defs[id]["gimbal"] = 180  # a virtual gun on a ship that is not aimed at the target: let it bear
	arena.weapons.defs[id]["range"] = maxf(float(arena.weapons.defs[id]["range"]), 1500.0)  # the flak guns are short ranged; the target is 800 px off
	return arena.add_mount(0, id, Vector2(15.5, 12.5))


func _fire(gun: int) -> bool:
	arena.ships[0].cooldowns.clear()
	return arena.fire(0, gun, arena.cell_to_world(1, Vector2i(8, 15)))


func _effects(kind: String) -> Array:
	return arena.events.filter(func(e): return e["type"] == "effect" and e["kind"] == kind)


func test_every_weapon_fires_through_the_arena_and_leaves_its_mark() -> void:
	for id in _all(0):
		var gun := _duel(id)
		var fired := _fire(gun)
		check(fired, id + " fires")
		for i in 240:
			arena.step(DT * 4.0)
		if MARK.has(id):
			check(not _effects(MARK[id]).is_empty(), "%s leaves a %s on the target" % [id, MARK[id]])
		var hurt := arena.events.any(func(e): return e["type"] in ["hit", "breach", "effect"])
		check(hurt, id + " reaches the target")
		if id in SELF:
			check(not _effects("self_room").is_empty(), id + " costs its own room")
	eq(Content.errors(), [], "no content problems")


func test_the_steam_lance_starts_fires_in_its_own_room_about_one_shot_in_ten() -> void:
	var gun := _duel("mire_steam_lance")
	var fires := 0
	for i in 400:
		_fire(gun)
		for e in arena.events:
			fires += 1 if e["type"] == "ignite" else 0
		arena.events.clear()
	check(fires >= 20 and fires <= 70, "about 40 fires in 400 shots, got %d" % fires)


func test_a_weapon_that_needs_its_race_loses_power_without_one() -> void:
	for pair in [["prismatic_prism_lens", "prismatic", "damage", 0.5], ["prismatic_glimmer_turret", "prismatic", "rate", 0.4], ["grundl_grapple_harpoon", "grundl", "rate", 0.3]]:
		var gun := _duel(pair[0])
		var base := arena.weapons.def(pair[0])
		var m: Dictionary = arena.ships[0].mounts[gun]
		var bare := Effects.adjust(arena, 0, gun, m, base)
		if pair[2] == "damage":
			near(float(bare["damage"]), float(base["damage"]) * pair[3], pair[0] + ": half the damage with nobody")
		else:
			near(float(bare["cooldown"]), float(base["cooldown"]) / pair[3], pair[0] + ": a slower cooldown with nobody")
		var ship: Ship = arena.ships[0].ship
		ship.crew.append(CrewMember.new("Pat", Pathfinder.centre_of(Vector2i(12, 12)), "human"))
		ship.manned[gun] = "Pat"
		eq(float(Effects.adjust(arena, 0, gun, m, base)[("damage" if pair[2] == "damage" else "cooldown")]), float(bare[("damage" if pair[2] == "damage" else "cooldown")]), pair[0] + ": a human at the post changes nothing")
		ship.crew.append(CrewMember.new("Kin", Pathfinder.centre_of(Vector2i(12, 12)), pair[1]))
		ship.manned[gun] = "Kin"
		eq(Effects.adjust(arena, 0, gun, m, base)[("damage" if pair[2] == "damage" else "cooldown")], base[("damage" if pair[2] == "damage" else "cooldown")], pair[0] + ": a %s at the post gives full power" % pair[1])


# --- the components, with and without their race --------------------------------------------------------

## A reactor and `part_id` in the fixture room, one cable between them; the part is `uid`, and `powered` says so.
func _rig(part_id: String, reactor_id := "reactor_mk1", rot := 0) -> Dictionary:
	var ship := Fixture.room_ship()
	var d := {"ship": ship}
	d["reactor"] = Fixture.put(ship, reactor_id, 10, 10)
	d["part"] = Fixture.put(ship, part_id, 15, 10, rot)
	Fixture.wire(ship, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	return d


func _crew(ship: Ship, name: String, species: String, x := 12, y := 14) -> CrewMember:
	var m := CrewMember.new(name, Pathfinder.centre_of(Vector2i(x, y)), species)
	ship.crew.append(m)
	ship.refresh()
	return m


func _supply(ship: Ship) -> float:
	ship.refresh()
	var total := 0.0
	for n in ship.power_state["networks"]:
		total += n["supply"]
	return total


func test_the_song_reactor_adds_one_power_per_prismatic_in_its_room_up_to_three() -> void:
	var rig := _rig("prismatic_song_reactor", "reactor_mk1")
	var ship: Ship = rig["ship"]
	var lone := _supply(ship) - 8.0  # the Reactor Mk1 gives 8
	near(lone, 8.0 * 1.3, "with nobody it makes the neon line's 10.4", 0.01)
	for i in 4:
		_crew(ship, "P%d" % i, "prismatic", 11 + i, 14)
		near(_supply(ship) - 8.0, 8.0 * 1.3 + minf(float(i + 1), 3.0), "%d Prismatic in the room" % (i + 1), 0.01)
	var human := _rig("prismatic_song_reactor")
	_crew(human["ship"], "H", "human", 12, 14)
	near(_supply(human["ship"]) - 8.0, 8.0 * 1.3, "a human adds nothing", 0.01)


func test_the_overclock_engine_runs_at_full_thrust_only_with_a_mechanical_crew_member_in_its_room() -> void:
	var rig := _rig("gauntling_overclock_engine", "reactor_mk1", 2)
	var ship: Ship = rig["ship"]
	var uid: int = rig["part"]
	near(float(Abilities.thrust_boost(ship).get(uid, 1.0)), 0.667, "alone it makes the Mk2's 18 of its 27", 0.001)
	_crew(ship, "Human", "human")
	near(float(Abilities.thrust_boost(ship).get(uid, 1.0)), 0.667, "a human in the room does not help", 0.001)
	_crew(ship, "Rook", "gauntling")
	near(float(Abilities.thrust_boost(ship).get(uid, 1.0)), 1.0, "a Gauntling does", 0.001)
	near(float(ship.effective("gauntling_overclock_engine")["stats"]["thrust"]), 27.0, "27 thrust at full")


func test_the_hauler_thrusters_need_a_grundl_to_tend_the_fuel_cells() -> void:
	var rig := _rig("grundl_hauler_thrusters", "reactor_mk1", 2)
	var ship: Ship = rig["ship"]
	var uid: int = rig["part"]
	near(float(Abilities.thrust_boost(ship).get(uid, 1.0)), 0.625, "without a Grundl they make the Mk2's 18 of 29", 0.001)
	_crew(ship, "Human", "human")
	near(float(Abilities.thrust_boost(ship).get(uid, 1.0)), 0.625, "a human cannot tend them", 0.001)
	_crew(ship, "Bram", "grundl")
	near(float(Abilities.thrust_boost(ship).get(uid, 1.0)), 1.0, "a Grundl can", 0.001)


func test_the_freight_shield_recharges_only_while_a_grundl_restocks_its_cells() -> void:
	var rig := _rig("grundl_freight_shield", "reactor_mk2")
	var ship: Ship = rig["ship"]
	var powered: Dictionary = ship.power_state["powered"]
	near(Abilities.recharge_rate(ship, powered), 0.0, "alone its used layers never come back", 0.001)
	_crew(ship, "Human", "human")
	near(Abilities.recharge_rate(ship, powered), 0.0, "a human does not restock", 0.001)
	_crew(ship, "Bram", "grundl")
	near(Abilities.recharge_rate(ship, powered), 1.0, "a Grundl does", 0.001)


func test_the_arc_core_graft_bay_and_overclock_engine_shock_organic_crew_but_not_mechanical_ones() -> void:
	# [the part under test, the reactor beside it, the consumer]
	for set in [["gauntling_arc_core", "gauntling_arc_core", "oxygen_gen"], ["gauntling_graft_bay", "reactor_mk2", "gauntling_graft_bay"], ["gauntling_overclock_engine", "reactor_mk2", "gauntling_overclock_engine"]]:
		var rig := _rig(set[2], set[1], 2 if set[2] == "gauntling_overclock_engine" else 0)
		var ship: Ship = rig["ship"]
		var human := _crew(ship, "Human", "human")
		var rook := _crew(ship, "Rook", "gauntling", 13, 14)
		var before_h := human.hp
		var before_r := rook.hp
		for i in 100:
			Abilities.tick(ship, 0.1)
		near(before_h - human.hp, 10.0, set[0] + ": a human loses 1 hp a second over 10 s", 0.5)
		near(before_r - rook.hp, 0.0, set[0] + ": a Gauntling is mechanical and loses nothing", 0.001)


func test_wet_rooms_slow_everyone_but_the_mire() -> void:
	for id in ["mire_mist_projector", "mire_bog_mortar", "mire_spray_deck"]:
		var rig := _rig(id, "reactor_mk1")
		var ship: Ship = rig["ship"]
		var human := _crew(ship, "Human", "human")
		var mire := _crew(ship, "Fen", "mire", 13, 14)
		var f_h := Abilities.work_mult(ship, human)
		var f_m := Abilities.work_mult(ship, mire)
		check(f_h < 1.0 and f_h >= 0.8, "%s: a human works at %s in the damp room" % [id, str(f_h)])
		near(f_m, 1.0, id + ": a Mire does not mind", 0.001)


func test_the_cargo_deck_and_graft_bay_change_who_works_fast() -> void:
	var rig := _rig("grundl_cargo_deck")
	var ship: Ship = rig["ship"]
	var human := _crew(ship, "Human", "human")
	var bram := _crew(ship, "Bram", "grundl", 13, 14)
	near(Abilities.work_mult(ship, human), 0.8, "anyone but a Grundl works x0.8 in the Cargo Deck", 0.001)
	near(Abilities.work_mult(ship, bram), 1.0, "a Grundl at full speed", 0.001)
	var g := _rig("gauntling_graft_bay")
	var gs: Ship = g["ship"]
	var h2 := _crew(gs, "Human", "human")
	var rook := _crew(gs, "Rook", "gauntling", 13, 14)
	near(Abilities.work_mult(gs, rook), 2.0, "a Gauntling works x2 in the Graft Bay", 0.001)
	near(Abilities.work_mult(gs, h2), 1.0, "a human is not faster", 0.001)


func test_the_resonance_helm_gives_evasion_only_with_a_prismatic_in_its_room() -> void:
	var rig := _rig("prismatic_resonance_helm")
	var ship: Ship = rig["ship"]
	near(Abilities.evasion_add(ship), 0.0, "alone it is a plain helm", 0.001)
	_crew(ship, "Human", "human")
	near(Abilities.evasion_add(ship), 0.0, "a human beside it changes nothing", 0.001)
	_crew(ship, "Lux", "prismatic", 13, 14)
	near(Abilities.evasion_add(ship), 0.1, "a Prismatic gives it evasion +0.1", 0.001)
	check(float(_comps().def("prismatic_resonance_helm")["power"]) < float(_comps().def("helm")["power"]), "and it draws more power than a plain helm")


func test_the_wetwell_and_rain_shield_and_garden_bay_risk_fires_and_the_mire_cancel_it() -> void:
	var c := _comps()
	for pair in [["mire_wetwell_reactor", 0.02], ["mire_rain_shield", 0.02], ["sporeling_garden_bay", 0.015]]:
		var found := false
		for a in c.def(pair[0])["abilities"]:
			for s in a.get("side_effects", []):
				if s["type"] == "fire_risk":
					near(float(s["rate"]), pair[1], pair[0] + ": its fire risk a second")
					found = true
		check(found, pair[0] + " risks fires")
	var mire := CrewMember.new("Fen", Vector2.ZERO, "mire")
	var human := CrewMember.new("Hu", Vector2.ZERO, "human")
	var tm: Dictionary = TraitSet.of(mire)
	var th: Dictionary = TraitSet.of(human)
	check(float(tm["work_mult"]["extinguish"]) >= 2.0 and float(tm["damage_taken"]["fire"]) <= 0.5, "a Mire puts fires out twice as fast and burns half")
	check(float(th["work_mult"]["extinguish"]) == 1.0 and float(th["damage_taken"]["fire"]) == 1.0, "a human does neither")


func test_the_sporeling_parts_that_eat_air_are_met_by_the_sporelings_own_air() -> void:
	var bloom := _rig("sporeling_bloom_reactor", "reactor_mk1")
	var ship: Ship = bloom["ship"]
	var before := ship.atmosphere.pressure_at(Vector2i(12, 12))
	for i in 300:
		Abilities.tick(ship, 0.1)
	check(ship.atmosphere.pressure_at(Vector2i(12, 12)) < before - 0.05, "the Bloom Reactor eats the room's air: %s -> %s" % [str(before), str(ship.atmosphere.pressure_at(Vector2i(12, 12)))])
	var aura: Dictionary = TraitSet.of(CrewMember.new("Sp", Vector2.ZERO, "sporeling"))["aura"]
	check(float(aura["o2_per_s"]) > 0.0, "and a Sporeling's aura puts air back")


# --- the homeland stores and the hand weapons ---------------------------------------------------------

func test_each_homeland_store_sells_its_racial_parts() -> void:
	for race in HOME:
		var r: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/regions/%s.json" % HOME[race]))
		for id in _all_of(race, 0) + _all_of(race, 1):
			check(r["stock"].has(id), "%s sells %s" % [HOME[race], id])
			check(int(r["stock"][id]) > 0, id + ": at a price")


func test_the_ten_hand_weapons_follow_the_class_figures() -> void:
	var seen := {}
	for race in RACES:
		for id in _all_of(race, 2):
			var h := Content.entry("hand_weapons", id)
			check(not h.is_empty(), id + " is a hand weapon")
			check(not seen.has(id), id + " once")
			seen[id] = true
			eq(h["culture"], race, id + ": its race's culture")
			check(CLASSES.has(h["class"]), "%s: class %s" % [id, h["class"]])
			var base: Array = CLASSES[h["class"]]
			var changed := false
			for i in 3:
				var got := float(h[["damage", "rate", "range"][i]])
				check(got >= base[i] * 0.8 - 1e-6 and got <= base[i] * 1.2 + 1e-6, "%s: %s within 20 percent of the %s figure" % [id, ["damage", "rate", "range"][i], h["class"]])
				changed = changed or absf(got - base[i]) > 1e-6
			check(str(h.get("notes", "")) != "", id + ": a note")
			if changed:
				check(str(h["notes"]).contains("%"), id + ": a shifted figure says by how much")
			eq(h["art"], id, id + ": its art is art/items/<id>.png (not drawn yet)")
	eq(seen.size(), 10, "ten")
	var classes := {}
	for id in seen:
		classes[Content.entry("hand_weapons", id)["class"]] = true
	check(classes.has("pistol") and classes.has("rifle") and classes.has("heavy") and classes.has("melee") and classes.has("tool"), "all five classes are covered")
