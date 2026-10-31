extends "res://tests/base_test.gd"
## The active abilities of crew members (docs/CONTENT.md section 16; scripts/crew/crew_abilities.gd, crew_fx.gd,
## characters.gd, ui/crew_bar.gd): the vocabulary, one test per ability, cooldowns, selection and G, the crew bar,
## the character schema and recruiting a character. The characters come from the fixture pack
## tests/fixtures/packs/crew/ (the real data/characters.json is empty until the writers fill it).

const Fixture = preload("res://tests/fixture_ship.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Characters = preload("res://scripts/crew/characters.gd")
const Content = preload("res://scripts/data/content.gd")
const CrewAbilities = preload("res://scripts/crew/crew_abilities.gd")
const CrewBar = preload("res://scripts/ui/crew_bar.gd")
const CrewFx = preload("res://scripts/crew/crew_fx.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const Events = preload("res://scripts/space/events.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Radar = preload("res://scripts/space/radar.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")

const FIXTURES := "res://tests/fixtures/packs/crew"
const IDS: Array[String] = ["power_system", "overclock", "heal_burst", "rally", "repair_burst", "extinguish", "seal_breach", "shield_layer", "scan", "hack", "berserk", "phase"]


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _fixture(folder := FIXTURES) -> void:
	Content.packs_root = folder
	CrewMember._species = {}  # the species table is read once: read it again with the pack's species


func _done() -> void:
	Content.packs_root = ""
	CrewMember._species = {}


## `base` with the keys of `extra` laid over it (a copy).
func _with(base: Dictionary, extra: Dictionary) -> Dictionary:
	var d := base.duplicate(true)
	d.merge(extra, true)
	return d


## A crew member on `ship` whose body has its top-left cell on (x, y), carrying ability `id`.
func _crew(ship: Ship, who: String, x: int, y: int, id: String, species := "human") -> CrewMember:
	var m := CrewMember.new(who, Pathfinder.centre_of(Vector2i(x, y)), species)
	m.ability = {"id": id}
	ship.crew.append(m)
	return m


## The test room cut in two by a wall at x = 15 (the west room is x 9..14, the east x 16..21).
func _split(ship: Ship) -> void:
	for y in range(9, 17):
		ship.grid.force_tile(Vector2i(15, y), "wall")
	ship.mark_dirty()
	ship.refresh()


## A reactor (x 10..13), `part_id` at (15, 10) and one cable between them.
func _rig(part_id: String, rot := 0) -> Dictionary:
	var ship := Fixture.room_ship()
	var d := {"ship": ship}
	d["reactor"] = Fixture.put(ship, "reactor_mk1", 10, 10)
	d["part"] = Fixture.put(ship, part_id, 15, 10, rot)
	Fixture.wire(ship, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	return d


func _run(ship: Ship, seconds: float, step := 0.1) -> void:
	for i in roundi(seconds / step):
		CrewAbilities.tick(ship, step)


func _supply(ship: Ship) -> float:
	ship.refresh()
	var total := 0.0
	for n in ship.power_state["networks"]:
		total += n["supply"]
	return total


# --- the vocabulary -------------------------------------------------------------------------------------

func test_the_vocabulary_has_the_twelve_abilities_and_the_data_passes_its_checks() -> void:
	var v := CrewAbilities.vocabulary()
	for id in IDS:
		check(v.has(id), "the vocabulary has " + id)
	eq(v.size(), IDS.size(), "and nothing else")
	for p in CrewAbilities.problems():
		check(false, p)
	eq(Content.list("characters").filter(func(c): return Content.origin("characters", c["id"]) == "core"), [], "the core character list is empty: the characters come from packs")
	check(FileAccess.file_exists("res://data/characters.json"), "in its file")


func test_an_ability_is_the_vocabulary_with_the_members_own_numbers_over_it() -> void:
	var m := CrewMember.new("T")
	eq(CrewAbilities.of(m), {}, "no ability")
	check(CrewAbilities.can_use(Ship.new("s"), m) != "", "and so nothing to use")
	m.ability = {"id": "heal_burst"}
	var a := CrewAbilities.of(m)
	eq([a["name"], a["cooldown"], a["params"]["amount"]], ["Heal Burst", 30.0, 30.0], "the defaults")
	m.ability = {"id": "heal_burst", "cooldown": 12, "params": {"amount": 50}}
	a = CrewAbilities.of(m)
	eq([a["cooldown"], float(a["params"]["amount"])], [12.0, 50.0], "the member's cooldown and params win")
	m.ability = {"id": "overclock", "params": {"mult": 2.0}}
	a = CrewAbilities.of(m)
	eq([float(a["params"]["mult"]), float(a["params"]["duration"]), float(a["params"]["rest"])], [2.0, 10.0, 5.0], "a param left out keeps its default")
	m.ability = {"id": "no_such_thing"}
	eq(CrewAbilities.of(m), {}, "an id the vocabulary lacks is no ability")


func test_a_species_entry_may_carry_an_ability() -> void:
	_fixture()
	var m := CrewMember.new("Pythia", Vector2.ZERO, "fx_oracle")
	eq(m.ability["id"], "scan", "the species' ability is theirs")
	var a := CrewAbilities.of(m)
	eq([a["params"]["duration"], a["cooldown"]], [12.0, 45.0], "its own params over the defaults")
	m.set_species("human")
	eq(m.ability, {}, "another species, no ability")
	_done()
	eq(CrewMember.new("X").ability, {}, "no species of the real data has one yet")


# --- power_system ---------------------------------------------------------------------------------------

func test_power_system_powers_the_system_beside_them_for_a_while() -> void:
	var ship := Fixture.room_ship()
	var fab := Fixture.put(ship, "fabricator", 15, 10)  # x 15..18, y 10..11: no cable, no reactor
	var m := _crew(ship, "Socket", 13, 10, "power_system")
	ship.refresh()
	check(not ship.power_state["powered"][fab], "it has no power")
	var r := CrewAbilities.use(ship, m)
	check(r["ok"], "used: " + r["text"])
	ship.refresh()
	check(ship.power_state["powered"][fab], "it runs without a reactor")
	eq(CrewFx.power_bonus(ship), {fab: 3.0}, "+3 power on it")
	near(m.ability_cd, 45.0, "the cooldown starts")
	_run(ship, 19.0)
	ship.refresh()
	check(ship.power_state["powered"][fab], "still on after 19 s")
	_run(ship, 1.2)
	ship.refresh()
	check(not ship.power_state["powered"][fab], "off after its 20 s")
	eq(CrewFx.power_bonus(ship), {}, "the effect is gone")


func test_power_system_needs_a_system_within_reach() -> void:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "fabricator", 15, 10)
	var m := _crew(ship, "Socket", 10, 14, "power_system")
	var r := CrewAbilities.use(ship, m)
	check(not r["ok"] and r["text"].contains("within reach"), "too far: " + r["text"])
	near(m.ability_cd, 0.0, "a refusal costs nothing")


func test_power_system_prefers_a_system_with_no_power() -> void:
	var d := _rig("fabricator")  # the fabricator is on the reactor's cable
	var ship: Ship = d["ship"]
	var gen := Fixture.put(ship, "oxygen_gen", 15, 12)  # below the fabricator, with no cable
	ship.refresh()
	check(ship.power_state["powered"][d["part"]] and not ship.power_state["powered"][gen], "the fabricator runs, the generator does not")
	var m := _crew(ship, "Socket", 13, 11, "power_system")  # touches the reactor, the fabricator and the generator
	var r := CrewAbilities.use(ship, m)
	check(r["ok"], r["text"])
	eq(CrewFx.power_bonus(ship).keys(), [gen], "the one with no power gets it")


# --- overclock ------------------------------------------------------------------------------------------

func test_overclock_runs_the_manned_engine_faster_then_burns_it_out() -> void:
	var d := _rig("engine_mk1", 2)
	var ship: Ship = d["ship"]
	var m := _crew(ship, "Rook", 12, 14, "overclock")
	var r := CrewAbilities.use(ship, m)
	check(not r["ok"] and r["text"].contains("not manning"), "not at a post: " + r["text"])
	ship.manned[d["part"]] = "Rook"
	r = CrewAbilities.use(ship, m)
	check(r["ok"], "manning the engine: " + r["text"])
	near(Abilities.thrust_boost(ship)[d["part"]], 1.5, "thrust x1.5")
	check(ship.power_state["powered"][d["part"]], "powered meanwhile")
	_run(ship, 10.2)
	eq(Abilities.thrust_boost(ship), {}, "the boost is over after 10 s")
	ship.refresh()
	check(not ship.power_state["powered"][d["part"]], "and the engine is off")
	check(ship.disabled_uids().has(d["part"]), "held offline")
	_run(ship, 4.6)
	check(ship.disabled_uids().has(d["part"]), "still off at 4.8 s into the 5")
	_run(ship, 0.6)
	ship.refresh()
	check(not ship.disabled_uids().has(d["part"]) and ship.power_state["powered"][d["part"]], "back after 5 s")
	check(not CrewAbilities.use(ship, m)["ok"], "and the cooldown (40 s) is still running")


func test_overclock_on_a_reactor_makes_more_power() -> void:
	var d := _rig("laser_mk1")
	var ship: Ship = d["ship"]
	var m := _crew(ship, "Rook", 12, 14, "overclock")
	near(_supply(ship), 8.0, "the reactor makes 8")
	ship.manned[d["reactor"]] = "Rook"
	check(CrewAbilities.use(ship, m)["ok"], "overclock the reactor")
	near(_supply(ship), 12.0, "x1.5: 12")


func test_overclock_on_a_weapon_cools_it_down_faster() -> void:
	var d := _rig("laser_mk1")
	var ship: Ship = d["ship"]
	var m := _crew(ship, "Rook", 12, 14, "overclock")
	ship.manned[d["part"]] = "Rook"
	var a := Arena.new()
	var i := a.add_ship(ship)
	check(a.fire(i, d["part"], Vector2(0.0, -1000.0)), "a manned laser fires")
	near(a.cooldown_left(i, d["part"]), 1.08, "manned: 10 percent less than 1.2 s", 0.03)
	check(CrewAbilities.use(ship, m)["ok"], "overclock the laser")
	var b := Arena.new()
	var j := b.add_ship(ship)
	check(b.fire(j, d["part"], Vector2(0.0, -1000.0)), "fires again")
	near(b.cooldown_left(j, d["part"]), 1.08 / 1.5, "and cools down 1.5 times as fast", 0.03)


func test_overclock_on_a_shield_recharges_its_layers_faster() -> void:
	var d := _rig("shield_mk1")
	var ship: Ship = d["ship"]
	var m := _crew(ship, "Rook", 12, 14, "overclock")
	var a := Arena.new()
	var co = a.ships[a.add_ship(ship)]
	co.sector_layers[0] = 0.0
	co.sector_timers[0] = [Vector2(2.0, 1.0)]
	Shields.tick(co, 1.4)
	near(co.sector_layers[0], 0.0, "a layer takes 2 s to come back", 1e-6)
	ship.manned[d["part"]] = "Rook"
	check(CrewAbilities.use(ship, m)["ok"], "overclock the shield")
	co.sector_layers[0] = 0.0
	co.sector_timers[0] = [Vector2(2.0, 1.0)]
	Shields.tick(co, 1.4)
	near(co.sector_layers[0], 1.0, "overclocked, 1.4 s is enough", 1e-6)


func test_overclock_on_the_helm_raises_its_evasion() -> void:
	var ship := Fixture.room_ship()
	var helm := Fixture.put(ship, "helm", 19, 10)
	var m := _crew(ship, "Rook", 17, 10, "overclock")
	ship.manned[helm] = "Rook"
	near(Jobs.evasion_bonus(ship), 0.05, "a manned helm: +5 percent")
	check(CrewAbilities.use(ship, m)["ok"], "overclock the helm")
	near(Jobs.evasion_bonus(ship), 0.075, "x1.5")


func test_overclock_refuses_a_part_it_cannot_speed_up() -> void:
	var ship := Fixture.room_ship()
	var med := Fixture.put(ship, "medbay", 15, 10)
	var m := _crew(ship, "Rook", 13, 10, "overclock")
	ship.manned[med] = "Rook"
	var r := CrewAbilities.use(ship, m)
	check(not r["ok"] and r["text"].contains("cannot be overclocked"), r["text"])


# --- heal_burst, rally, repair_burst -----------------------------------------------------------------------

func test_heal_burst_heals_everyone_in_the_room_and_only_there() -> void:
	var ship := Fixture.room_ship()
	_split(ship)
	var doc := _crew(ship, "Doc", 10, 10, "heal_burst")
	var a := _crew(ship, "A", 12, 12, "")
	var down := _crew(ship, "Down", 10, 13, "")
	var far := _crew(ship, "Far", 18, 10, "")
	a.hp = 20.0
	down.hp = 0.0
	far.hp = 10.0
	var r := CrewAbilities.use(ship, doc)
	check(r["ok"], r["text"])
	near(a.hp, 50.0, "+30")
	near(down.hp, 30.0, "a downed crewmate is up again")
	check(not down.is_down(), "on their feet")
	near(far.hp, 10.0, "the other room is not touched")
	near(doc.ability_cd, 30.0, "30 s cooldown")
	var again := CrewAbilities.use(ship, doc)
	check(not again["ok"] and again["text"].contains("on cooldown 30 s"), again["text"])


func test_a_basalt_is_a_bad_medic_even_with_a_burst() -> void:
	var ship := Fixture.room_ship()
	var rock := _crew(ship, "Rock", 10, 10, "heal_burst", "basalt")
	var a := _crew(ship, "A", 12, 12, "")
	a.hp = 10.0
	check(CrewAbilities.use(ship, rock)["ok"], "used")
	near(a.hp, 25.0, "half of 30")


func test_heal_burst_with_nobody_hurt_does_nothing_and_costs_nothing() -> void:
	var ship := Fixture.room_ship()
	var doc := _crew(ship, "Doc", 10, 10, "heal_burst")
	var r := CrewAbilities.use(ship, doc)
	check(not r["ok"] and r["text"].contains("nobody"), r["text"])
	near(doc.ability_cd, 0.0, "no cooldown")


func test_rally_speeds_the_others_in_the_room_for_a_while() -> void:
	var ship := Fixture.room_ship()
	_split(ship)
	var lead := _crew(ship, "Lead", 10, 10, "rally")
	var mate := _crew(ship, "Mate", 12, 12, "")
	var far := _crew(ship, "Far", 18, 10, "")
	near(TraitSet.work_rate(ship, mate, "repair"), 1.0, "before: normal speed")
	var r := CrewAbilities.use(ship, lead)
	check(r["ok"], r["text"])
	near(TraitSet.work_rate(ship, mate, "repair"), 1.5, "a mate in the room works x1.5")
	near(TraitSet.work_rate(ship, lead, "repair"), 1.0, "the caller does not")
	near(TraitSet.work_rate(ship, far, "repair"), 1.0, "nor does the other room")
	_run(ship, 14.0)
	near(TraitSet.work_rate(ship, mate, "repair"), 1.5, "still at 14 s")
	_run(ship, 1.2)
	near(TraitSet.work_rate(ship, mate, "repair"), 1.0, "over after 15 s")


func test_rally_needs_company() -> void:
	var ship := Fixture.room_ship()
	var lead := _crew(ship, "Lead", 10, 10, "rally")
	var r := CrewAbilities.use(ship, lead)
	check(not r["ok"] and r["text"].contains("nobody else"), r["text"])
	near(lead.ability_cd, 0.0, "no cooldown")


func test_repair_burst_mends_the_hurt_system_beside_them() -> void:
	var ship := Fixture.room_ship()
	var reactor := Fixture.put(ship, "reactor_mk1", 10, 10)
	var gen := Fixture.put(ship, "oxygen_gen", 15, 10)
	var fixer := _crew(ship, "Old Hob", 14, 12, "repair_burst")  # touches the reactor (x 13) and the generator (x 15)
	ship.components.instances[reactor]["hp"] = 5
	ship.components.instances[gen]["hp"] = 0
	ship.components.instances[gen]["status"] = "disabled"
	var r := CrewAbilities.use(ship, fixer)
	check(r["ok"], r["text"])
	near(float(ship.components.instances[gen]["hp"]), 4.0, "the most hurt one, +4 hp")
	eq(ship.components.instances[gen]["status"], "ok", "a disabled part works again once it has hp")
	near(float(ship.components.instances[reactor]["hp"]), 5.0, "the other is left")
	for step in [["the reactor, now the most hurt (5 of 8)", reactor, 8.0], ["the generator, 4 of 5", gen, 5.0]]:
		fixer.ability_cd = 0.0
		check(CrewAbilities.use(ship, fixer)["ok"], "again: " + step[0])
		near(float(ship.components.instances[step[1]]["hp"]), step[2], "capped at its maximum: " + step[0])
	fixer.ability_cd = 0.0
	var none := CrewAbilities.use(ship, fixer)
	check(not none["ok"] and none["text"].contains("nothing hurt"), none["text"])
	near(fixer.ability_cd, 0.0, "nothing spent")


# --- extinguish, seal_breach, shield_layer ---------------------------------------------------------------------

func test_extinguish_puts_out_the_fires_of_the_room() -> void:
	var ship := Fixture.room_ship()
	_split(ship)
	var m := _crew(ship, "Sister Vell", 10, 10, "extinguish")
	var none := CrewAbilities.use(ship, m)
	check(not none["ok"] and none["text"].contains("no fire"), none["text"])
	Fire.ignite(ship, Vector2i(11, 12))
	Fire.ignite(ship, Vector2i(13, 14))
	Fire.ignite(ship, Vector2i(18, 12))
	var r := CrewAbilities.use(ship, m)
	check(r["ok"], r["text"])
	eq(ship.fires.keys(), [Vector2i(18, 12)], "only the fire in the other room is left")
	near(m.ability_cd, 25.0, "cooldown")


func test_seal_breach_seals_the_nearest_breach_at_once() -> void:
	var ship := Fixture.room_ship()
	var m := _crew(ship, "Fixer", 10, 12, "seal_breach")
	var none := CrewAbilities.use(ship, m)
	check(not none["ok"] and none["text"].contains("no breach"), none["text"])
	ship.grid.breach(Vector2i(8, 12))
	ship.grid.breach(Vector2i(8, 14))
	ship.grid.breach(Vector2i(22, 12))  # 12 cells away: out of reach
	ship.mark_dirty()
	var r := CrewAbilities.use(ship, m)
	check(r["ok"], r["text"])
	eq(ship.grid.breached.keys().size(), 2, "one of three sealed")
	check(not ship.grid.breached.has(Vector2i(8, 12)), "the nearest")
	check(ship.grid.tile_flag(ship.grid.get_tile(Vector2i(8, 12)), "solid"), "the wall is back")
	m.ability_cd = 0.0
	m.ability = {"id": "seal_breach", "params": {"count": 3}}
	check(CrewAbilities.use(ship, m)["ok"], "again, for three at a time")
	eq(ship.grid.breached.keys(), [Vector2i(22, 12)], "the far one stays: out of reach")


func test_shield_layer_adds_a_layer_for_a_while() -> void:
	var d := _rig("shield_mk1")
	var ship: Ship = d["ship"]
	var m := _crew(ship, "Warden", 12, 14, "shield_layer")
	var bare := Fixture.room_ship()
	var m0 := _crew(bare, "Warden", 12, 14, "shield_layer")
	var refused := CrewAbilities.use(bare, m0)
	check(not refused["ok"] and refused["text"].contains("shield"), refused["text"])
	var a := Arena.new()
	var i := a.add_ship(ship)
	eq(a.ships[i].layers_cap, 1, "one layer")
	var r := CrewAbilities.use(ship, m)
	check(r["ok"], r["text"])
	eq(Abilities.extra_layers(ship), 1, "+1 layer")
	a.sync(i)
	eq(a.ships[i].layers_cap, 2, "the arena's bubble holds two")
	_run(ship, 10.2)
	a.sync(i)
	eq(a.ships[i].layers_cap, 1, "back to one after 10 s")


# --- scan, hack ---------------------------------------------------------------------------------------------

func test_scan_reveals_hidden_contacts_and_reports_the_enemy() -> void:
	var d := _rig("helm")
	var ship: Ship = d["ship"]
	var m := _crew(ship, "Pythia", 12, 14, "scan")
	var s = Campaign.new(1).sector_at("n01")
	var here := Vector2(10000.0, 10000.0)
	s.pois = [{"id": "h", "type": "wreck", "name": "wreck", "pos": here + Vector2(2500.0, 0.0), "visibility": "hidden", "event_type": "wreck_field", "state": "new", "enemy": "", "main": false}]
	s.ambient = []
	s.ship_pos = here
	eq(Radar.contacts(s, ship).size(), 0, "a hidden contact 2,500 px away is not seen")
	var r := CrewAbilities.use(ship, m)
	check(r["ok"], r["text"])
	near(CrewFx.scan_left(ship), 20.0, "20 s of scan")
	var list := Radar.contacts(s, ship)
	eq(list.size(), 1, "now the radar shows it")
	eq(list[0]["known_type"], "wreck", "and says what it is")
	_run(ship, 20.2)
	eq(Radar.contacts(s, ship).size(), 0, "hidden again after 20 s")
	m.ability_cd = 0.0
	var enemy := Fixture.room_ship()
	enemy.name = "Pirate"
	Fixture.put(enemy, "laser_mk1", 15, 10)
	r = CrewAbilities.use(ship, m, enemy)
	check(r["ok"] and r["text"].contains("Pirate") and r["text"].contains("1 weapon"), "the enemy is reported: " + r["text"])


func test_hack_knocks_an_enemy_system_offline_from_the_helm() -> void:
	var d := _rig("helm")
	var ship: Ship = d["ship"]
	var m := _crew(ship, "Cipher", 12, 14, "hack")
	var foe := _rig("laser_mk1")
	var enemy: Ship = foe["ship"]
	check(not CrewAbilities.use(ship, m, enemy)["ok"], "not at the helm")
	ship.manned[d["part"]] = "Cipher"
	var no_enemy := CrewAbilities.use(ship, m)
	check(not no_enemy["ok"] and no_enemy["text"].contains("no enemy"), no_enemy["text"])
	enemy.refresh()
	check(enemy.power_state["powered"][foe["part"]], "the enemy laser works")
	var r := CrewAbilities.use(ship, m, enemy)
	check(r["ok"], r["text"])
	enemy.refresh()
	check(not enemy.power_state["powered"][foe["part"]], "and now it is off")
	var a := Arena.new()
	var i := a.add_ship(enemy)
	a.sync(i)
	check(not a.fire(i, foe["part"], Vector2(0.0, -1000.0)), "it cannot fire")
	_run(enemy, 4.8)
	enemy.refresh()
	check(not enemy.power_state["powered"][foe["part"]], "still off at 4.8 s")
	_run(enemy, 0.4)
	enemy.refresh()
	check(enemy.power_state["powered"][foe["part"]], "back after 5 s")
	m.ability_cd = 0.0
	var bare := Fixture.room_ship()
	var nothing := CrewAbilities.use(ship, m, bare)
	check(not nothing["ok"] and nothing["text"].contains("nothing"), nothing["text"])


# --- berserk, phase ---------------------------------------------------------------------------------------

func test_berserk_stores_the_melee_multiplier() -> void:
	var ship := Fixture.room_ship()
	var m := _crew(ship, "Brute", 10, 10, "berserk", "prismatic")  # crystal bodies hit at x0.5
	near(CrewAbilities.melee_mult(ship, m), 0.5, "before: the species' x0.5")
	var r := CrewAbilities.use(ship, m)
	check(r["ok"], r["text"])
	near(CrewAbilities.melee_mult(ship, m), 1.0, "berserk doubles it")
	near(CrewFx.berserk_mult(ship, m), 2.0, "x2 on its own")
	_run(ship, 10.2)
	near(CrewAbilities.melee_mult(ship, m), 0.5, "over after 10 s")


func test_phase_steps_through_the_wall_ahead() -> void:
	var ship := Fixture.room_ship()
	_split(ship)
	var m := _crew(ship, "Ghost", 13, 10, "phase")
	m.facing = Vector2.RIGHT
	var blocker := _crew(ship, "Blocker", 16, 10, "")
	var jam := CrewAbilities.use(ship, m)
	check(jam["ok"] and m.anchor() == Vector2i(18, 10), "someone stands on the first spot beyond: the next free one: " + jam["text"])
	ship.crew.erase(blocker)
	m.ability_cd = 0.0
	m.pos = Pathfinder.centre_of(Vector2i(13, 10))
	m.path = [Vector2i(14, 10)]
	var r := CrewAbilities.use(ship, m)
	check(r["ok"], r["text"])
	eq(m.anchor(), Vector2i(16, 10), "on the far side of the 1-cell wall")
	check(ship.atmosphere.room_at(m.cell()) != ship.atmosphere.room_at(Vector2i(12, 12)), "in the other room")
	check(m.path.is_empty(), "their walk is dropped")
	m.ability_cd = 0.0
	m.facing = Vector2.LEFT
	var back := CrewAbilities.use(ship, m)
	check(back["ok"] and m.anchor() == Vector2i(13, 10), "and back: " + back["text"])
	m.ability_cd = 0.0
	m.facing = Vector2.UP
	var none := CrewAbilities.use(ship, m)
	check(not none["ok"] and none["text"].contains("no wall"), "nothing but the hull ahead: " + none["text"])
	near(m.ability_cd, 0.0, "a refusal costs nothing")


# --- cooldowns ---------------------------------------------------------------------------------------------

func test_a_cooldown_counts_down_in_game_time_and_blocks_the_use() -> void:
	var ship := Fixture.room_ship()
	var m := _crew(ship, "Doc", 10, 10, "heal_burst")
	var hurt := _crew(ship, "A", 12, 12, "")
	hurt.hp = 1.0
	eq(CrewAbilities.can_use(ship, m), "", "ready")
	check(CrewAbilities.use(ship, m)["ok"], "used")
	eq(CrewAbilities.can_use(ship, m), "on cooldown 30 s", "blocked, and it says for how long")
	_run(ship, 10.0)
	eq(CrewAbilities.can_use(ship, m), "on cooldown 20 s", "20 s left")
	CrewAbilities.tick(ship, 0.0)
	near(m.ability_cd, 20.0, "no time, no change (the world paused)")
	_run(ship, 19.9)
	check(CrewAbilities.can_use(ship, m) != "", "0.1 s short")
	_run(ship, 0.2)
	eq(CrewAbilities.can_use(ship, m), "", "ready again")
	near(m.ability_cd, 0.0, "and never below 0")
	m.hp = 0.0
	eq(CrewAbilities.can_use(ship, m), "is down", "a downed crew member cannot")
	m.hp = 50.0
	m.stun = 2.0
	eq(CrewAbilities.can_use(ship, m), "is stunned", "nor a stunned one")


func test_the_sim_ticks_the_cooldowns_of_every_ship() -> void:
	var sim := ShipSim.new()
	var mine := Fixture.room_ship()
	var foe := Fixture.room_ship()
	sim.ships = [mine, foe]
	var a := _crew(mine, "Doc", 10, 10, "heal_burst")
	var b := _crew(foe, "Grub", 10, 10, "heal_burst")
	a.ability_cd = 30.0
	b.ability_cd = 30.0
	sim.step(1.0)
	near(a.ability_cd, 29.0, "the player's crew")
	near(b.ability_cd, 29.0, "and the enemy's")
	sim.step(0.0)
	near(a.ability_cd, 29.0, "no time passes when the world does not step")
	CrewAbilities.use(mine, _crew(mine, "Brute", 14, 12, "berserk"))
	sim.set_paused(true, "build mode")
	sim.step(5.0)
	near(a.ability_cd, 29.0, "the world is paused (build mode): the cooldown stands still")
	near(CrewFx.list(mine)[0]["left"], 10.0, "and so does a running effect")
	sim.set_paused(false)
	sim.step(1.0)
	near(a.ability_cd, 28.0, "and it goes on afterwards")
	near(CrewFx.list(mine)[0]["left"], 9.0, "(the effect too)")
	sim.free()


func test_the_card_state_reads_ready_cooling_running_or_blocked() -> void:
	var ship := Fixture.room_ship()
	var m := _crew(ship, "Brute", 10, 10, "berserk")
	eq(CrewAbilities.card(ship, m)["state"], "ready", "ready")
	CrewAbilities.use(ship, m)
	var c := CrewAbilities.card(ship, m)
	eq(c["state"], "running", "its effect runs")
	near(c["active_left"], 10.0, "10 s left")
	_run(ship, 10.2)
	c = CrewAbilities.card(ship, m)
	eq(c["state"], "cooling", "then it cools")
	near(c["cooldown_left"], 35.0 - 10.2, "with the rest of 35 s", 0.01)
	m.ability_cd = 0.0
	m.stun = 1.0
	eq(CrewAbilities.card(ship, m)["state"], "blocked", "stunned: blocked")
	eq(CrewAbilities.card(ship, _crew(ship, "Plain", 12, 12, ""))["state"], "none", "no ability, no card icon")


# --- selection and the crew bar ---------------------------------------------------------------------------------

## A crew view on a test ship in play mode, with a crew bar bound to it.
func _view(ship: Ship) -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [ship]
	var build := BuildMode.new()
	build.build_on = false
	var view := CrewView.new()
	view.sim = sim
	view.build = build
	var bar := CrewBar.new()
	bar.view = view
	bar.size = Vector2(1600.0, 900.0)
	view._bar = bar
	return {"view": view, "bar": bar, "sim": sim, "build": build}


func _free(d: Dictionary) -> void:
	for k in d:
		d[k].free()


func test_a_click_picks_the_nearest_crew_member_and_g_uses_their_ability() -> void:
	var ship := Fixture.room_ship()
	var doc := _crew(ship, "Doc", 10, 10, "heal_burst")
	var mate := _crew(ship, "Mate", 14, 12, "")
	mate.hp = 10.0
	var d := _view(ship)
	var view: CrewView = d["view"]
	eq(view.pick_at(doc.pos + Vector2(0.5, 0.3)), doc, "a click on a body picks it")
	eq(view.pick_at(mate.pos), mate, "or another")
	eq(view.pick_at(Vector2(19.0, 15.0)), null, "empty floor picks nobody")
	check(view.press_ability().begins_with("Select a crew member"), "G with nobody selected says so")
	view.select(doc)
	var text: String = view.press_ability()
	check(text.contains("heals"), "G uses the selected one's ability: " + text)
	near(mate.hp, 40.0, "and it worked")
	near(doc.ability_cd, 30.0, "cooldown")
	check(d["bar"].flash_text.contains("heals"), "the bar says so")
	view.select(mate)
	check(not view.use_ability(mate)["ok"], "a crew member with no ability: nothing")
	_free(d)


func test_nothing_is_used_while_build_mode_pauses_the_world() -> void:
	var ship := Fixture.room_ship()
	var doc := _crew(ship, "Doc", 10, 10, "heal_burst")
	var mate := _crew(ship, "Mate", 14, 12, "")
	mate.hp = 10.0
	var d := _view(ship)
	var view: CrewView = d["view"]
	d["build"].build_on = true
	check(not view.bar_visible(), "the bar is put away in build mode")
	check(not view.use_ability(doc)["ok"], "and G does nothing")
	near(mate.hp, 10.0, "no healing")
	near(doc.ability_cd, 0.0, "no cooldown")
	d["build"].build_on = false
	check(view.bar_visible(), "play mode shows it")
	d["build"].combat = true
	check(view.bar_visible(), "and so does a fight")
	_free(d)


func test_a_selection_is_dropped_when_the_member_is_gone() -> void:
	var ship := Fixture.room_ship()
	var doc := _crew(ship, "Doc", 10, 10, "heal_burst")
	var d := _view(ship)
	var view: CrewView = d["view"]
	view.select(doc)
	ship.crew.erase(doc)
	check(view.press_ability().begins_with("Select"), "no longer aboard: nothing to use")
	_free(d)


func test_the_crew_bar_stacks_cards_up_from_the_bottom_right() -> void:
	var screen := Vector2(1600.0, 900.0)
	var rects := CrewBar.card_rects(4, screen)
	eq(rects.size(), 4, "a card each")
	for i in rects.size():
		check(Rect2(Vector2.ZERO, screen).encloses(rects[i]), "card %d is on the screen" % i)
		near(rects[i].end.x, screen.x - CrewBar.MARGIN, "right-aligned")
		if i > 0:
			near(rects[i].position.y, rects[i - 1].end.y + CrewBar.GAP, "stacked")
	near(rects[3].end.y, screen.y - CrewBar.MARGIN, "the last sits at the bottom")
	var many := CrewBar.card_rects(30, screen)
	var cols := {}
	for r in many:
		cols[r.position.x] = true
		check(r.position.y >= CrewBar.TOP_RESERVED - CrewBar.CARD.y, "no card runs into the HUD at the top")
	check(cols.size() > 1, "a second column starts to the left when the first is full")
	for i in many.size():
		for j in range(i + 1, many.size()):
			check(not many[i].intersects(many[j]), "cards %d and %d do not overlap" % [i, j])
	var icon := CrewBar.icon_rect(rects[0])
	check(rects[0].encloses(icon), "the ability icon is inside its card")


func test_clicking_a_card_selects_and_clicking_its_icon_uses_the_ability() -> void:
	var ship := Fixture.room_ship()
	var plain := _crew(ship, "Plain", 10, 10, "")
	var doc := _crew(ship, "Doc", 12, 12, "heal_burst")
	plain.hp = 10.0
	var d := _view(ship)
	var bar: CrewBar = d["bar"]
	var view: CrewView = d["view"]
	var rects := CrewBar.card_rects(2, bar.size)
	eq(bar.card_at(rects[1].get_center()), 1, "the second card")
	eq(bar.card_at(Vector2(100.0, 100.0)), -1, "the world is not a card")
	check(bar._has_point(rects[0].get_center()) and not bar._has_point(Vector2(100.0, 100.0)), "only the cards take the mouse")
	eq(bar.click(rects[0].get_center()), "select", "a click on a card")
	eq(view.selected, plain, "selects that member")
	near(doc.ability_cd, 0.0, "nothing used")
	eq(bar.click(rects[1].position + Vector2(20.0, 20.0)), "select", "a click away from the icon")
	eq(view.selected, doc, "selects Doc")
	eq(bar.click(CrewBar.icon_rect(rects[1]).get_center()), "use", "a click on the icon")
	near(doc.ability_cd, 30.0, "uses the ability")
	near(plain.hp, 40.0, "healing Plain")
	eq(bar.click(CrewBar.icon_rect(rects[0]).get_center()), "select", "a member with no ability has no icon")
	eq(bar.click(Vector2(5.0, 5.0)), "", "a click off the cards is not ours")
	_free(d)


# --- characters -----------------------------------------------------------------------------------------------

func test_the_fixture_characters_pass_every_check() -> void:
	_fixture()
	_noerrors(Content.errors())
	eq(Characters.ids(), ["fx_socket", "fx_lamp", "fx_medic"], "three characters from the pack")
	_noerrors(CrewAbilities.problems())
	_done()


func _noerrors(list: Array) -> void:
	for p in list:
		check(false, str(p))


func test_a_character_species_one_of_the_30_gives_its_body_look_and_ability() -> void:
	_fixture()
	var m = CrewMember.from_character("fx_socket", Vector2(5.0, 5.0))
	eq([m.name, m.character, m.species], ["Socket", "fx_socket", "basalt"], "named, and a Basalt")
	near(m.max_hp, 140.0, "a Basalt's body")
	check(m.traits().has("no_breath") and m.traits().has("suit"), "the species' traits and the personal list")
	check(Abilities.meets(m, ["no_breath|suit"]), "the personal trait counts for operator needs")
	eq(m.ability["id"], "power_system", "their ability")
	eq(CrewAbilities.of(m)["cooldown"], 30.0, "their own cooldown")
	eq(CrewAbilities.of(m)["params"]["power"], 2.0, "their own power")
	eq(m.look["suit"], "#8a6f4a", "the rig tint colours the outfit")
	eq(m.head, "rock_b", "and the head frame is theirs")
	eq(m.rig(), "basalt", "drawn on the Basalt rig")
	eq(CrewMember.from_character("nobody"), null, "an unknown id makes no one")
	_done()


func test_a_one_of_a_kind_character_has_a_species_of_its_own() -> void:
	_fixture()
	var m = CrewMember.from_character("fx_lamp")
	eq([m.name, m.species], ["Lamplighter", "unique:fx_lamp"], "named, in a species of its own")
	near(m.max_hp, 60.0, "the unique species' hp")
	near(m.speed, CrewMember.BASE_SPEED * 1.2, "and speed")
	eq(m.rig(), "gauntling", "its rig")
	eq(m.sidearm(), "service_pistol", "and sidearm")
	var t := TraitSet.of(m)
	near(t["o2_use"], 0.0, "its listed trait: it does not breathe")
	near(t["aura"]["heal_per_s"], 0.5, "the key written inline on the species")
	near(t["work_mult"]["repair"], 1.5, "and the bag of personal keys on the character")
	eq(m.head, "lamp", "the head frame")
	near(TraitSet.of(CrewMember.new("Plain"))["work_mult"]["repair"], 1.0, "(an ordinary human is untouched)")
	eq(Characters.label(Characters.entry("fx_lamp")), "Lantern Spirit", "the species name for the UI")
	eq(Characters.label(Characters.entry("fx_socket")), "Basalt", "or the real one's")
	_done()
	eq(CrewMember.species_def("unique:fx_lamp"), {}, "without the pack the species is gone")


func test_the_character_schema_catches_every_mistake() -> void:
	var ok := {"id": "fx_ok", "name": "Okay", "species": "human", "ability": {"id": "rally"}, "obtained": "x", "lore": "y"}
	eq(CrewAbilities.character_problems(ok), [], "a minimal character is fine")
	var cases := {
		"snake_case": _with(ok, {"id": "Not Snake"}),
		"must be text": _with(ok, {"lore": ""}),
		"needs exactly one of species and unique_species": _with(ok, {"unique_species": {"name": "X", "hp": 50, "speed": 1.0}}),
		"is not in data/species.json": _with(ok, {"species": "klingon"}),
		"needs an ability": {"id": "fx_ok", "name": "Okay", "species": "human", "obtained": "x", "lore": "y"},
		"is not in the vocabulary": _with(ok, {"ability": {"id": "teleport"}}),
		"has no param": _with(ok, {"ability": {"id": "rally", "params": {"power": 3}}}),
		"cooldown must be a number above 0": _with(ok, {"ability": {"id": "rally", "cooldown": 0}}),
		"unknown key": _with(ok, {"colour": "red"}),
		"rig tint must be #rrggbb": _with(ok, {"rig": {"tint": "red"}}),
		"is not a head frame": _with(ok, {"rig": {"head": "tophat"}}),
		"rig has the unknown key": _with(ok, {"rig": {"hat": "x"}}),
		"is not defined": _with(ok, {"traits": ["telepathy"]}),
		"unknown trait key": _with(ok, {"traits": {"super_strength": 2}}),
		"must be a number": _with(ok, {"traits": {"hp_mult": "lots"}}),
		"unique_species must be an object": {"id": "fx_ok", "name": "Okay", "unique_species": "a ghost", "ability": {"id": "rally"}, "obtained": "x", "lore": "y"},
		"hp must be a number above 0": {"id": "fx_ok", "name": "Okay", "unique_species": {"name": "X", "speed": 1.0}, "ability": {"id": "rally"}, "obtained": "x", "lore": "y"},
		"has no art folder": {"id": "fx_ok", "name": "Okay", "unique_species": {"name": "X", "hp": 50, "speed": 1.0, "rig": "nothing"}, "ability": {"id": "rally"}, "obtained": "x", "lore": "y"},
	}
	for want in cases:
		var got := CrewAbilities.character_problems(cases[want])
		var hit := false
		for p in got:
			hit = hit or p.contains(want)
		check(hit, "'%s' is reported (got %s)" % [want, str(got)])
	var bad_species := CrewAbilities.ability_problems("x", {"id": "scan", "colour": 1})
	check(not bad_species.is_empty(), "an ability entry with a stray key is reported too")


func test_two_characters_may_not_share_a_name() -> void:
	_fixture(FIXTURES + "_dup")
	var found := false
	for p in CrewAbilities.problems():
		found = found or (p.contains("'Twin'") and p.contains("fx_twin_a"))
	check(found, "the second Twin is reported: " + str(CrewAbilities.problems()))
	_done()


# --- recruiting ---------------------------------------------------------------------------------------------

func _camp() -> Campaign:
	return Campaign.new(1, {}, Events.new("res://tests"))


func _aboard() -> Ship:
	var s: Ship = Ship.from_design("res://data/ships/starter_rustbucket.json")
	Jobs.spawn_crew(s)
	return s


func test_the_recruit_effect_can_name_a_character() -> void:
	_fixture()
	var c := _camp()
	var ship := _aboard()
	var n := ship.crew.size()
	var r: Dictionary = c.events.apply({"recruit": {"character": "fx_socket"}}, c, ship, {"id": "n99", "type": "empty", "place": ""})
	eq(ship.crew.size(), n + 1, "one more aboard")
	var m: CrewMember = ship.crew[-1]
	eq([m.name, m.species, m.character], ["Socket", "basalt", "fx_socket"], "as themselves")
	eq(m.ability["id"], "power_system", "with their ability")
	check(r["lines"].has("Socket (Basalt) joins the crew"), "said: " + str(r["lines"]))
	c.events.apply({"recruit": {"character": "fx_socket"}}, c, ship, {"id": "n99", "type": "empty", "place": ""})
	eq(ship.crew.size(), n + 1, "a character comes aboard only once")
	c.events.apply({"recruit": {"character": "fx_lamp"}}, c, ship, {"id": "n99", "type": "empty", "place": ""})
	eq(ship.crew[-1].species, "unique:fx_lamp", "a one-of-a-kind character too")
	var before := ship.crew.size()
	c.events.apply({"recruit": {"character": "nobody"}}, c, ship, {"id": "n99", "type": "empty", "place": ""})
	eq(ship.crew.size(), before, "an unknown one adds no one")
	c.events.apply({"recruit": {"species": "fenn", "name": "Juno2"}}, c, ship, {"id": "n99", "type": "empty", "place": ""})
	eq(ship.crew[-1].character, "", "an ordinary recruit is not a character")
	_done()


func test_the_event_validator_knows_characters() -> void:
	_fixture()
	var e := Events.new("res://tests")
	var fx := func(effects: Dictionary) -> Dictionary:
		return {"id": "recruit_test", "type": "empty", "weight": 10, "once": false, "requires": {}, "text": "T",
			"choices": [{"text": "Go", "outcomes": [{"weight": 100, "text": "Done", "effects": effects}]}]}
	e.add(fx.call({"recruit": {"character": "fx_socket"}}), "test.json")
	eq(e.validate().size(), 0, "a real character id is fine, with no species")
	var bad := Events.new("res://tests")
	bad.add(fx.call({"recruit": {"character": "nobody"}}), "test.json")
	var errs := bad.validate()
	check(errs.size() == 1 and errs[0].contains("unknown character 'nobody'"), "an unknown one is named: " + str(errs))
	_done()


func test_a_saved_run_still_loads_with_abilities_in_play() -> void:
	var ship := Fixture.room_ship()
	var m := _crew(ship, "Doc", 10, 10, "heal_burst")
	CrewAbilities.use(ship, m)
	var d: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))
	var back := Ship.new_starter()
	eq(back.load_dict(d), "", "the ship loads")
	eq(back.ability_state, Abilities.fresh_state(), "with fresh ability state (effects are not saved)")
