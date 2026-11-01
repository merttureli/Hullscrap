extends "res://tests/base_test.gd"
## Abilities (scripts/sim/abilities.gd): triggering, duration and cooldown, operator needs, what they
## change in flight, power and shields, their side effects, the combat keys and the bar, determinism.

const Fixture = preload("res://tests/fixture_ship.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const WeaponBar = preload("res://scripts/ui/weapon_bar.gd")

const PIRATE := "res://data/ships/pirate_raider.json"


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A reactor (x 10..11, y 10..13) and `part_id` (x 15..) joined by one cable in the test room. Returns {ship, reactor, part}.
func _rig(part_id: String, reactor_id := "reactor_mk1") -> Dictionary:
	var ship := Fixture.room_ship()
	var d := {"ship": ship}
	d["reactor"] = Fixture.put(ship, reactor_id, 10, 10)
	d["part"] = Fixture.put(ship, part_id, 15, 10, 2)  # turned round: a bare engine pushes opposite its nozzle, and the nozzle of rotation 0 points up
	Fixture.wire(ship, [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	return d


## Put crew member `who` at the station of part `uid`, as the crew jobs do (ship.manned).
func _man(ship: Ship, uid: int, who: String) -> void:
	if ship.crew.filter(func(m): return m.name == who).is_empty():
		ship.crew.append(CrewMember.new(who, Vector2(12.0, 12.0)))
	ship.manned[uid] = who


func _run(ship: Ship, seconds: float, step := 0.1, rng: RandomNumberGenerator = null) -> void:
	for i in roundi(seconds / step):
		Abilities.tick(ship, step, rng)


func _sim(ship: Ship) -> ShipSim:
	var sim := ShipSim.new()
	sim.ships = [ship]
	return sim


func _supply(ship: Ship) -> float:
	ship.refresh()
	var total := 0.0
	for n in ship.power_state["networks"]:
		total += n["supply"]
	return total


func _demand(ship: Ship) -> float:
	ship.refresh()
	var total := 0.0
	for n in ship.power_state["networks"]:
		total += n["demand"]
	return total


# --- the data ----------------------------------------------------------------------------------------

func test_the_content_follows_the_brief() -> void:
	var c := Ship.new("t").components
	var a: Dictionary = c.def("afterburner")["abilities"][0]
	eq([c.def("afterburner")["family"], c.def("afterburner")["tier"], c.def("afterburner")["size"], c.def("afterburner")["stats"]["thrust"], c.def("afterburner")["unique"]],
		["engine", 2, [4, 2], 16.0, true], "Afterburner: unique, engine, tier 2, 4x2, thrust 16")
	eq([a["type"], a["key"], a["duration"], a["cooldown"], a["effects"], a["operator_needs"]],
		["active", "engine", 8.0, 30.0, {"stat_mult": {"thrust": 1.4}}, ["no_breath|suit"]], "Afterburn")
	eq(a["side_effects"], [{"type": "drain_o2", "rate": 0.15}, {"type": "heat", "rate": 12.0}], "its side effects")
	var o: Dictionary = c.def("reactor_neon_mk1")["abilities"][0]
	eq([o["name"], o["key"], o["duration"], o["cooldown"], o["effects"], o["side_effects"]],
		["Overdrive", "utility", 10.0, 40.0, {"stat_mult": {"power": 1.5}}, [{"type": "heat", "rate": 15.0}]], "Overdrive")
	var s: Dictionary = c.def("engine_scrap_mk1")["abilities"][0]
	eq([s["name"], s["key"], s["duration"], s["cooldown"], s["effects"]], ["Sputter Boost", "engine", 4.0, 15.0, {"stat_mult": {"thrust": 1.25}}], "Sputter Boost")
	eq(s["side_effects"], [{"type": "self_damage", "rate": 0.3}, {"type": "fire_risk", "rate": 0.05}], "its side effects")
	for id in c.ids():
		if c.def(id)["family"] == "shield":
			eq([c.def(id)["abilities"][0]["id"], c.def(id)["abilities"][0]["key"], c.def(id)["abilities"][0]["effects"]], ["overcharge", "shield", {"shield_layer": 1.0}], id + " has Overcharge")
	eq(CrewMember.config()["traits"]["Rook"], ["suit"], "a starter crew member wears a suit")
	for key in ["courier", "prism"]:
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/ships/starter_%s.json" % key))
		eq(d["cargo"].get("afterburner"), 1, key + " carries an Afterburner")


# --- triggering, duration, cooldown -------------------------------------------------------------------

func test_an_ability_runs_for_its_duration_then_rests_for_its_cooldown() -> void:
	var d := _rig("engine_scrap_mk1")
	var ship: Ship = d["ship"]
	var part: int = d["part"]
	eq(Abilities.can_trigger(ship, part), "", "ready: no operator is needed")
	eq(Abilities.trigger(ship, part), "", "triggered")
	near(Abilities.active_left(ship, part, "sputter_boost"), 4.0, "runs for 4 s")
	eq(Abilities.trigger(ship, part), "already active", "not twice")
	_run(ship, 3.9)
	near(Abilities.active_left(ship, part, "sputter_boost"), 0.1, "0.1 s left after 3.9 s")
	_run(ship, 0.2)
	near(Abilities.active_left(ship, part, "sputter_boost"), 0.0, "over after 4 s")
	near(Abilities.cooldown_left(ship, part, "sputter_boost"), 15.0, "the cooldown starts when the effect ends", 0.11)
	check(Abilities.can_trigger(ship, part).begins_with("on cooldown 1"), "refused while resting: " + Abilities.can_trigger(ship, part))
	_run(ship, 14.0)
	eq(Abilities.can_trigger(ship, part), "on cooldown 1 s", "1 s to go")
	_run(ship, 1.1)
	eq(Abilities.can_trigger(ship, part), "", "ready again")
	check(ship.events.any(func(e): return e["text"] == "Sputter Boost on") and ship.events.any(func(e): return e["text"] == "Sputter Boost off"), "the chronicle says when it starts and stops")
	eq(Abilities.hud_line(ship), "", "no HUD line when nothing runs")


func test_refusals_unpowered_out_of_action_and_unknown() -> void:
	var d := _rig("engine_scrap_mk1")
	var ship: Ship = d["ship"]
	var part: int = d["part"]
	for status in ["disabled", "overheated", "malfunction"]:
		ship.components.instances[part]["status"] = status
		eq(Abilities.trigger(ship, part), status, "a %s part refuses" % status)
	ship.components.instances[part]["status"] = "ok"
	ship.cables.cells.clear()
	ship.mark_dirty()
	eq(Abilities.trigger(ship, part), "unpowered", "no cable, no power")
	eq(Abilities.trigger(ship, d["reactor"]), "no such ability", "a standard reactor has none")
	eq(Abilities.trigger(ship, 999), "no such ability", "no such part")


func test_a_running_ability_stops_when_its_part_goes_out() -> void:
	var d := _rig("engine_scrap_mk1")
	var ship: Ship = d["ship"]
	Abilities.trigger(ship, d["part"])
	ship.components.instances[d["part"]]["status"] = "disabled"
	Abilities.tick(ship, 0.1)
	near(Abilities.active_left(ship, d["part"], "sputter_boost"), 0.0, "stopped")
	near(Abilities.cooldown_left(ship, d["part"], "sputter_boost"), 15.0, "and resting")
	eq(Abilities.thrust_boost(ship), {}, "no boost left")


func test_removing_the_part_drops_its_state() -> void:
	var d := _rig("engine_scrap_mk1")
	var ship: Ship = d["ship"]
	Abilities.trigger(ship, d["part"])
	ship.components.remove_at(Vector2i(15, 10))
	Abilities.tick(ship, 0.1)
	eq(ship.ability_state["slots"], {}, "no state for a part that is gone")


# --- operators ---------------------------------------------------------------------------------------

func test_the_afterburner_needs_a_suited_or_breathless_operator_at_the_engine() -> void:
	var d := _rig("afterburner")
	var ship: Ship = d["ship"]
	var burner: int = d["part"]
	eq(Abilities.can_trigger(ship, burner), "needs a crew member with no_breath or suit at the engine", "unmanned")
	_man(ship, burner, "Juno")
	eq(Abilities.can_trigger(ship, burner), "needs a crew member with no_breath or suit at the engine", "manned by someone without a suit")
	_man(ship, burner, "Rook")
	eq(Abilities.can_trigger(ship, burner), "", "Rook wears a suit")
	ship.crew[ship.crew.size() - 1].hp = 0.0
	check(Abilities.can_trigger(ship, burner) != "", "a downed operator does not count")
	ship.crew[ship.crew.size() - 1].hp = 100.0
	CrewMember.config()["traits"]["Zed"] = ["no_breath"]  # a breathless species, only for this test
	_man(ship, burner, "Zed")
	eq(Abilities.can_trigger(ship, burner), "", "no_breath does as well")
	CrewMember.config()["traits"].erase("Zed")
	check(Abilities.meets(ship.crew[0], ["suit|no_breath"]) == false, "Juno meets neither")
	check(Abilities.meets(CrewMember.new("Rook"), ["suit"]) and not Abilities.meets(CrewMember.new("Rook"), ["suit", "no_breath"]), "every entry must be met, either side of a | will do")
	eq(Abilities.trigger(ship, burner), "needs a crew member with no_breath or suit at the engine", "Zed's trait is gone again")
	_man(ship, burner, "Rook")
	eq(Abilities.trigger(ship, burner), "", "Rook starts it")
	ship.manned.clear()
	_run(ship, 1.0)
	check(Abilities.active_left(ship, burner, "afterburn") > 0.0, "leaving the station does not stop it")


# --- thrust, in the arena -----------------------------------------------------------------------------

func test_thrust_x1_4_reaches_the_arena_and_ends_after_8_s() -> void:
	var d := _rig("afterburner")
	var ship: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(ship)
	near(a.ships[0].thrust, 16.0, "thrust 16 to begin with")
	eq(a.use_ability(0, d["part"]), "needs a crew member with no_breath or suit at the engine", "refused unmanned")
	_man(ship, d["part"], "Rook")
	eq(a.use_ability(0, d["part"]), "", "started")
	near(a.ships[0].thrust, 22.4, "thrust x1.4 at once")
	eq(a.events.back()["type"], "ability", "the arena logs it")
	a.step(7.9)
	near(a.ships[0].thrust, 22.4, "still boosted after 7.9 s")
	a.step(0.2)
	near(a.ships[0].thrust, 16.0, "back to 16 after 8 s")
	eq(a.use_ability(0, d["part"]), "on cooldown 30 s", "30 s of rest")
	a.step(29.0)
	eq(a.use_ability(0, d["part"]), "on cooldown 1 s", "1 s to go")
	a.step(1.1)
	eq(a.use_ability(0, d["part"]), "", "and ready again")


func test_the_boost_makes_the_ship_faster() -> void:
	var speeds := []
	for boost in [false, true]:
		var d := _rig("afterburner")
		var ship: Ship = d["ship"]
		Fixture.put(ship, "helm", 19, 10)
		Fixture.wire(ship, [Vector2i(18, 11), Vector2i(19, 11)])
		var a := Arena.new(1)
		a.add_ship(ship)
		_man(ship, d["part"], "Rook")
		if boost:
			a.use_ability(0, d["part"])
		a.set_input(0, 1.0, 0.0)
		a.step(2.0)
		speeds.append(a.ships[0].flight.vel.length())
	check(speeds[0] > 0.0 and speeds[1] > speeds[0] * 1.3, "faster with the Afterburner: %s" % [speeds])


func test_sputter_boost_is_x1_25_of_a_kickjet() -> void:
	var d := _rig("engine_scrap_mk1")
	var a := Arena.new(1)
	a.add_ship(d["ship"])
	near(a.ships[0].thrust, 9.0, "scrap thrust 10 x 0.9")
	a.use_ability(0, d["part"])
	near(a.ships[0].thrust, 9.0 * 1.25, "x1.25")


# --- side effects --------------------------------------------------------------------------------------

func test_drain_o2_lowers_the_room_air_and_heat_rises() -> void:
	var d := _rig("afterburner")
	var ship: Ship = d["ship"]
	var room: int = ship.atmosphere.room_at(ship.components.instances[d["part"]]["anchor"])
	near(ship.atmosphere.pressure_of(room), 1.0, "a full room")
	_man(ship, d["part"], "Rook")
	var sim := _sim(ship)
	Abilities.trigger(ship, d["part"])
	for i in 20:
		sim.step(0.1)  # 2 s
	near(ship.atmosphere.pressure_of(room), exp(-0.15 * 2.0), "0.15 of the air per second, 2 s", 0.002)
	var heat: float = ship.components.instances[d["part"]]["heat"]
	check(heat > 22.0 and heat < 26.0, "12 heat a second: %s" % heat)
	near(ship.components.instances[d["reactor"]]["heat"], 0.0, "other parts stay cool")
	eq(sim.hud_line(), "Abilities: Afterburn 6 s", "the HUD line shows it running")
	for i in 70:
		sim.step(0.1)
	eq(sim.hud_line(), "", "and no longer once it ended")
	check(ship.atmosphere.pressure_of(room) < 0.4, "the air stays down: %s" % ship.atmosphere.pressure_of(room))
	sim.free()


func test_overdrive_raises_the_power_supply_for_10_s() -> void:
	var d := _rig("oxygen_gen", "reactor_neon_mk1")
	var ship: Ship = d["ship"]
	var base: float = float(ship.components.def("reactor_neon_mk1")["power"]) * 1.3  # the neon line's x1.3
	near(_supply(ship), base, "a Prism Core: its power x 1.3")
	eq(Abilities.trigger(ship, d["reactor"]), "", "Overdrive needs no operator")
	near(_supply(ship), base * 1.5, "x1.5 while it runs")
	check(ship.power_state["powered"][d["part"]], "the consumer is still powered")
	_run(ship, 3.0)
	near(ship.components.instances[d["reactor"]]["heat"], 45.0, "15 heat a second goes into the reactor", 0.01)
	_run(ship, 6.9)
	near(_supply(ship), base * 1.5, "still on after 9.9 s")
	_run(ship, 0.2)
	near(_supply(ship), base, "back after 10 s")
	near(ship.components.instances[d["reactor"]]["heat"], 100.0, "the heat stops at the limit")


func test_a_power_spike_adds_demand_and_a_passive_runs_by_itself() -> void:
	var d := _rig("oxygen_gen")
	var ship: Ship = d["ship"]
	ship.components.by_id["oxygen_gen"]["abilities"] = [{"id": "surge", "name": "Surge", "type": "active", "key": "utility", "duration": 2, "cooldown": 5,
		"effects": {}, "side_effects": [{"type": "power_spike", "rate": 3}]}]
	near(_demand(ship), 2.0, "the generator draws 2")
	Abilities.trigger(ship, d["part"])
	near(_demand(ship), 5.0, "and 3 more while the spike lasts")
	check(ship.power_state["powered"][d["part"]], "powered still: 8 supply")
	_run(ship, 2.1)
	near(_demand(ship), 2.0, "back to 2")
	var e := _rig("engine_mk1")
	e["ship"].components.by_id["engine_mk1"]["abilities"] = [{"id": "hum", "name": "Hum", "type": "passive", "effects": {"stat_mult": {"thrust": 1.5}}, "side_effects": [{"type": "heat", "rate": 2}]}]
	eq(Abilities.thrust_boost(e["ship"]), {e["part"]: 1.5}, "a passive boost is on without a trigger")
	eq(Abilities.trigger(e["ship"], e["part"]), "passive", "and cannot be triggered")
	Abilities.tick(e["ship"], 1.0)
	near(e["ship"].components.instances[e["part"]]["heat"], 2.0, "its side effects apply too")


func test_sputter_boost_hurts_the_kickjet() -> void:
	var d := _rig("engine_scrap_mk1")
	var ship: Ship = d["ship"]
	Abilities.trigger(ship, d["part"])
	_run(ship, 4.1)  # no rng: no fires
	near(ship.components.instances[d["part"]]["hp"], 6.0 - 0.3 * 4.0, "0.3 hp a second for 4 s")
	d = _rig("engine_scrap_mk1")
	ship = d["ship"]
	ship.components.instances[d["part"]]["hp"] = 0.2
	Abilities.trigger(ship, d["part"])
	_run(ship, 1.0)
	eq(ship.components.instances[d["part"]]["status"], "disabled", "worn to nothing, it is disabled")
	check(ship.events.any(func(e): return e["text"] == "Kickjet is disabled"), "and the chronicle says so")


func test_fire_risk_needs_the_rng_and_starts_a_fire() -> void:
	var d := _rig("engine_scrap_mk1")
	var ship: Ship = d["ship"]
	ship.components.by_id["engine_scrap_mk1"]["abilities"][0]["side_effects"] = [{"type": "fire_risk", "rate": 1000.0}]
	Abilities.trigger(ship, d["part"])
	_run(ship, 1.0)
	check(ship.fires.is_empty(), "no rng, no fire")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_run(ship, 1.0, 0.1, rng)
	check(not ship.fires.is_empty(), "a certain risk lights the part")


# --- shields and weapons ---------------------------------------------------------------------------------

func test_the_shield_key_overcharges_through_the_data_ability() -> void:
	var d := _rig("shield_mk1")
	var ship: Ship = d["ship"]
	var a := Arena.new(1)
	a.add_ship(ship)
	eq([a.ships[0].layers, a.ships[0].layers_cap], [1, 1], "one layer")
	var r := a.use_key(0, "shield")
	eq([r["started"], r["refused"]], [[Abilities.slot_key(d["part"], "overcharge")], {}], "Space starts Overcharge")
	eq([a.ships[0].layers, a.ships[0].layers_cap], [2, 2], "one more layer")
	near(a.ships[0].overcharge_left, 6.0, "6 s")
	eq(a.use_key(0, "shield")["refused"].values(), ["already active"], "not twice")
	eq(a.use_key(0, "engine"), {"started": [], "refused": {}}, "no engine ability here")
	a.step(6.1)
	eq([a.ships[0].layers, a.ships[0].layers_cap], [1, 1], "gone after 6 s")
	check(a.ships[0].overcharge_cd > 8.0, "resting")
	eq(a.use_key(0, "shield")["refused"].values()[0].substr(0, 11), "on cooldown", "refused while resting")
	var two := Arena.new(1)
	two.add_ship(_rig("shield_mk1")["ship"])
	check(two.events.is_empty(), "no events yet")
	two.use_key(0, "shield")
	eq(two.events.back()["type"], "overcharge", "the arena logs the old event name for it")


func test_a_running_ability_can_change_every_weapon_cooldown() -> void:
	var results := []
	for haste in [false, true]:
		var d := _rig("shield_mk1")
		d["ship"].components.by_id["shield_mk1"]["abilities"] = [{"id": "haste", "name": "Haste", "type": "active", "key": "utility", "duration": 5, "cooldown": 5,
			"effects": {"charge_mult": 0.5}, "side_effects": []}]
		var a := Arena.new(1)
		a.add_ship(d["ship"])
		a.weapons.defs["slow"] = {"kind": "laser", "damage_type": "energy", "damage": 1, "gimbal": 180, "cooldown": 2.0, "range": 2000}
		var gun := a.add_mount(0, "slow", Vector2(15.5, 5.5))
		if haste:
			a.use_key(0, "utility")
		check(a.fire(0, gun, Vector2(0.0, -1000.0)), "fired")
		results.append(a.cooldown_left(0, gun))
	near(results[0], 2.0, "a plain cooldown", 0.02)
	near(results[1], 1.0, "halved while Haste runs", 0.02)


# --- the combat keys and the bar ---------------------------------------------------------------------------

func _fight(ship: Ship) -> Session:
	var s := Session.new()
	s.start(ship, Session.load_ship(PIRATE), 3)
	return s


func test_the_bar_presses_keys_and_flashes_the_reason() -> void:
	var d := _rig("afterburner", "reactor_mk2")
	var ship: Ship = d["ship"]
	Fixture.put(ship, "shield_mk1", 15, 12)
	Fixture.wire(ship, [Vector2i(15, 12)])
	var s := _fight(ship)
	eq(s.ability_slots().map(func(x): return x["key"]), ["engine", "shield"], "slots by key")
	var bar := WeaponBar.new()
	bar.session = s
	var r := bar.press("engine")
	var slot := Abilities.slot_key(d["part"], "afterburn")
	eq(r["refused"][slot], "needs a crew member with no_breath or suit at the engine", "refused unmanned")
	eq(bar.flashes[slot]["text"], r["refused"][slot], "and flashed in its slot")
	var af: Dictionary = s.ability_slots().filter(func(x): return x["id"] == "afterburn")[0]
	eq([s.ability_state(af)["state"], s.ability_state(af)["reason"]], ["blocked", r["refused"][slot]], "the slot reads blocked")
	_man(ship, d["part"], "Rook")
	r = bar.press("engine")
	eq(r["started"], [slot], "started with Rook at the engine")
	eq(s.ability_state(af)["state"], "active", "running")
	near(s.ability_state(af)["active_left"], 8.0, "8 s")
	for i in 60:
		s.tick(1.0 / 60.0)
	near(s.ability_state(af)["active_left"], 7.0, "a second later (the session's own arena ticks it)", 0.05)
	var key := InputEventKey.new()  # the real keys reach the same call
	key.keycode = KEY_SPACE
	key.pressed = true
	bar.flashes.clear()
	eq(s.arena.ships[Session.PLAYER].layers_cap, 1, "one shield layer")
	bar._unhandled_input(key)
	eq([s.arena.ships[Session.PLAYER].layers_cap, bar.flashes.size()], [2, 0], "Space overcharges the shield")
	bar.free()


func test_the_session_lists_the_pirates_overcharge_and_the_old_call_still_works() -> void:
	var s := Session.new()
	s.start(Session.load_ship(PIRATE), Session.load_ship(PIRATE), 3)
	var slots := s.ability_slots()
	eq(slots.map(func(x): return x["id"]), ["overcharge"], "one shield, one ability")
	eq(s.ability_state(slots[0])["state"], "ready", "ready")
	eq(s.arena.overcharge(Session.PLAYER), "", "the old call starts it")
	eq(s.ability_state(slots[0])["state"], "active", "running")
	eq(s.arena.overcharge(Session.PLAYER), "already overcharged", "with its old words")


# --- state, saves and replays ---------------------------------------------------------------------------------

func test_abilities_are_not_saved_and_a_load_clears_them() -> void:
	var d := _rig("engine_scrap_mk1")
	var ship: Ship = d["ship"]
	Abilities.trigger(ship, d["part"])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))
	check(not JSON.stringify(saved).contains("sputter"), "no ability state in the save")
	eq(ship.load_dict(saved), "", "loads")
	eq(ship.ability_state, Abilities.fresh_state(), "and starts afresh")
	_run(ship, 0.1)
	eq(Abilities.thrust_boost(ship), {}, "no boost after a load")


func test_the_sim_ticks_abilities_outside_a_fight_and_the_arena_in_one() -> void:
	var d := _rig("engine_scrap_mk1")
	var ship: Ship = d["ship"]
	var sim := _sim(ship)
	Abilities.trigger(ship, d["part"])
	sim.step(1.0)
	near(Abilities.active_left(ship, d["part"], "sputter_boost"), 3.0, "ShipSim counts it down alone")
	sim.ships = [ship, Ship.new("other")]
	sim.step(1.0)
	near(Abilities.active_left(ship, d["part"], "sputter_boost"), 3.0, "not in a fight: the arena does")
	var a := Arena.new(1)
	a.add_ship(ship)
	a.step(1.0)
	near(Abilities.active_left(ship, d["part"], "sputter_boost"), 2.0, "the arena counts a second", 0.02)
	sim.free()


func _replay() -> String:
	var d := _rig("engine_scrap_mk1")
	var ship: Ship = d["ship"]
	var sim := _sim(ship)
	for i in 400:
		if i % 150 == 0:
			Abilities.trigger(ship, d["part"])
		sim.step(0.1)
	sim.free()
	return JSON.stringify([ship.to_dict(), ship.ability_state, ship.events, ship.fires.size()])


func test_a_run_with_abilities_replays_exactly() -> void:
	var first := _replay()
	eq(_replay(), first, "same seed, same triggers, same state")
	check(first.contains("Sputter Boost on"), "and the run did use the ability")
