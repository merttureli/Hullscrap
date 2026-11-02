extends "res://tests/base_test.gd"
## The Ledger (scripts/sim/advisor.gd, data/advisor.json, the profile's Ledger fields): the checks measured on a built ship, the goals in order,
## the tips once per profile, the warnings once a stage, the three settings, the one-time question, the words validated against the check
## vocabulary and the numbers' format, and the promise that it only reads (the same seeded run with it on and off ends in the same state).

const Advisor = preload("res://scripts/sim/advisor.gd")
const Profile = preload("res://scripts/ui/profile.gd")
const Wall = preload("res://tests/fixture_wall.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Wardens = preload("res://scripts/space/wardens.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Characters = preload("res://scripts/crew/characters.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Content = preload("res://scripts/data/content.gd")

const FIXTURE := "res://tests/fixtures/progression.json"
const TMP := "user://test_advisor_profile.json"
const LINE_COLS := [Color("#9c5a33"), Color("#8d9aab"), Color("#3cf2ff")]  ## scrap, standard, neon (ui_kit.gd LINE_COLORS)
const PANEL := Color("#2a3340")  ## the lightest panel a keyword is drawn on


func _numbers() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


func _advisor(numbers = null) -> Advisor:
	return Advisor.new({}, _numbers() if numbers == null else numbers)


func _clean() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


## The wall fixture built up into a ship: three lasers and a net mouth on the wall, two reactors, a shield, a fabricator with a robot arm and a
## medbay, all on one cable. Supply 18, demand 6 + 3 + 2 + 1 + 2 = 14.
func _built() -> Ship:
	var ship := Wall.wall_ship(1, 0)
	var c = ship.components
	for y in range(22, 26):  # more floor behind the first rooms
		for x in range(8, 23):
			ship.grid.force_tile(Vector2i(x, y), "floor")
	for u0 in [-7, -3, 1]:
		check(c.place_mount(ship.grid, "laser_mk1", Wall.corner(0, u0, u0 + 3, -2, -1), 0) > 0, "a laser at u %d" % u0)
	check(c.place_mount(ship.grid, "net_mouth_scrap", Wall.corner(0, 5, 6, -2, -1), 0) > 0, "the net mouth")
	check(c.place(ship.grid, "reactor_mk1", Vector2i(9, 19), 1) > 0, "reactor 1")
	check(c.place(ship.grid, "reactor_mk1", Vector2i(13, 19), 1) > 0, "reactor 2")
	check(c.place(ship.grid, "shield_mk1", Vector2i(17, 19), 1) > 0, "the shield")
	for x in range(8, 16):  # the fabricator and its arm in a room of their own (a level needs the arm in the fabricator's room)
		for y in [21, 24]:
			ship.grid.force_tile(Vector2i(x, y), "wall")
	for y in range(21, 25):
		for x in [8, 15]:
			ship.grid.force_tile(Vector2i(x, y), "wall")
	check(c.place(ship.grid, "fabricator", Vector2i(9, 22), 0) > 0, "the fabricator")
	check(c.place(ship.grid, "robot_arm", Vector2i(13, 22), 0) > 0, "its arm")
	check(c.place(ship.grid, "medbay", Vector2i(17, 22), 1) > 0, "the medbay")
	for x in range(9, 22):  # a part is on the network when a cable runs through its footprint
		for y in [17, 19, 22]:
			ship.cables.place(ship.grid, Vector2i(x, y))
	for y in range(18, 22):
		ship.cables.place(ship.grid, Vector2i(21, y))
	ship.mark_dirty()  # (the walls were put in by hand)
	ship.refresh()
	return ship


func _campaign(seed_value := 5) -> Campaign:
	return Campaign.new(seed_value)


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


# --- the checks -----------------------------------------------------------------------------------------------

func test_each_check_computes_right_on_a_built_ship() -> void:
	var ship := _built()
	var c := _campaign()
	var v := Advisor.measure(ship, c, {})
	eq(v["intakes"], 1, "intakes: the net mouth on the wall")
	eq(v["guns"], 3, "guns: three powered lasers")
	eq(v["layers"], 1, "layers: one Shield Mk1 layer")
	eq(v["medbays"], 1, "medbays")
	eq(v["fab"], 2, "fab: a fabricator and a robot arm in its room is level 2")
	near(v["margin"], 4.0, "margin: 18 supplied, 14 asked")
	eq(v["damaged_blocks"], 0, "damaged_blocks: none on a fresh ship")
	eq(v["known"], ship.crafting.known.size(), "known: the blueprints held")
	eq(v["plates"], 0, "plates: none yet")
	check(float(v["power"]) > 0.0, "power: the ship has a rating")
	near(v["accel_ratio"], 1.0, "accel_ratio: against itself when there is no start to compare with")
	# an intake that is not mounted, a gun that has lost its power, a blown wall
	var bare := Wall.wall_ship(1, 0)
	eq(Advisor.measure(bare, c, {})["intakes"], 0, "an intake in the hold is not a working one")
	eq(Advisor.measure(bare, c, {})["guns"], 0, "nor a gun")
	eq(Advisor.measure(bare, c, {})["fab"], 0, "no fabricator, level 0")
	var uid: int = ship.components.instances.keys()[0]  # the first laser
	ship.components.instances[uid]["hp"] = 0.5
	eq(Advisor.measure(ship, c, {})["damaged_blocks"], 1, "a hurt part is a damaged block")
	ship.components.instances[uid]["hp"] = 100.0
	# plates: armour cells, counted against the start
	var base := Advisor.baseline(ship)
	eq(base["plates"], 0, "the start has no plates")
	for x in range(9, 14):
		ship.grid.force_tile(Vector2i(x, 15), "scrap_plate")
	ship.grid.force_tile(Vector2i(14, 15), "heavy_armor")
	eq(Advisor.measure(ship, c, base)["plates"], 6, "plates: six armour cells added")
	eq(Advisor.measure(ship, c, {"plates": 4})["plates"], 2, "and the start's own do not count")


func test_the_fuel_and_credit_checks_read_the_campaign() -> void:
	var ship := _built()
	var c := _campaign()
	ship.inventory.load_dict({"fuel": 10, "credits": 100, "scrap": 50})
	var v := Advisor.measure(ship, c, {})
	check(int(v["hops"]) > 0, "the exit beacon is some jumps away from the start")
	eq(v["station_hops"], 0, "and the start is a station")
	near(v["fuel_margin"], 10.0 - float(v["hops"]), "fuel_margin: fuel less one fuel a jump to the beacon (the ship has no engine: a whole fuel)")
	eq(v["toll"], Wardens.toll_of(c.warden), "the toll is the warden's")
	eq(v["credits_over_toll"], 100 - int(v["toll"]), "credits_over_toll: credits less the toll")
	c.current = c.drift.exit_id()
	v = Advisor.measure(ship, c, {})
	eq(v["hops"], 0, "at the beacon there are no jumps left")
	near(v["fuel_margin"], 10.0, "and all the fuel is spare")
	check(v["at_exit"] and v["warden_up"], "the warden holds the lane")
	c.flags[str(c.warden["flag"])] = true
	check(not Advisor.measure(ship, c, {})["warden_up"], "a cleared warden is not up")


func test_accel_ratio_is_against_the_start() -> void:
	var ship := Wall.wall_ship(1, 2)  # the wall faces the stern: the engine pushes the ship forward
	var c := _campaign()
	check(ship.components.place_mount(ship.grid, "engine_mk1", Wall.corner(2, -2, 1, -2, -1), 2) > 0, "an engine on the wall")
	check(ship.components.place(ship.grid, "reactor_mk1", Wall.corner(2, 2, 3, 1, 4), 0) > 0, "a reactor")
	for u in range(-1, 4):
		ship.cables.place(ship.grid, Wall.at(2, u, 1))
	ship.refresh()
	var base := Advisor.baseline(ship)
	check(float(base["accel"]) > 0.0, "the start accelerates")
	near(Advisor.measure(ship, c, base)["accel_ratio"], 1.0, "nothing added: the ratio is 1")
	for x in range(8, 23):
		for y in range(8, 15):
			if ship.grid.get_tile(Vector2i(x, y)) == "floor":
				ship.grid.force_tile(Vector2i(x, y), "heavy_armor")
	ship.mark_dirty()
	ship.refresh()
	var r: float = Advisor.measure(ship, c, base)["accel_ratio"]
	check(r < 0.9 and r > 0.0, "a ship loaded with armour is slower than its start: %s" % str(r))


# --- goals ---------------------------------------------------------------------------------------------------

func test_the_next_goal_follows_the_order_and_skips_met_ones() -> void:
	var a := _advisor()
	var v := {"intakes": 0, "guns": 0, "layers": 0, "medbays": 0, "fuel_margin": -3.0, "credits_over_toll": -10.0}
	eq(a.next_goal(v, 1)["id"], "s1_intake", "the intake first")
	v["intakes"] = 1
	eq(a.next_goal(v, 1)["id"], "s1_guns", "then the guns")
	eq(a.next_goal(v, 1)["progress"]["text"], "Guns 0/3", "with its progress")
	v["guns"] = 2
	eq(a.next_goal(v, 1)["progress"]["text"], "Guns 2/3", "two of three")
	v["guns"] = 3
	eq(a.next_goal(v, 1)["id"], "s1_cover", "a shield or a medbay is next")
	v["medbays"] = 1
	eq(a.next_goal(v, 1)["id"], "s1_fuel", "either one meets it")
	v["fuel_margin"] = 1.0
	eq(a.next_goal(v, 1)["id"], "s1_toll", "then the fuel")
	v["credits_over_toll"] = 0.0
	eq(a.next_goal(v, 1), {}, "all met: no next goal")
	# an earlier goal that is not met comes before later ones that are
	v = {"intakes": 0, "guns": 5, "layers": 2, "medbays": 1, "fuel_margin": 4.0, "credits_over_toll": 80.0}
	eq(a.next_goal(v, 1)["id"], "s1_intake", "the order is the lesson: the first unmet goal, even with the rest done")
	var rows := a.checklist(v, 1)
	eq(rows.map(func(r): return r["met"]), [false, true, true, true, true], "the checklist ticks what is done")
	eq(rows.size(), 5, "stage 1 has five goals")


func test_a_goal_reads_the_stage_numbers_and_leaves_out_what_it_cannot() -> void:
	var a := _advisor()
	var g3 := a.goals(3)
	eq(g3[0]["title"], "Brace: 6 guns behind 3 layers.", "{=key} holes are filled from the stage's row")
	var v := {"guns": 6, "layers": 3, "power": 33.0}
	check(not Advisor.goal_met(g3[0], v), "power under the stage's floor (34): not met")
	v["power"] = 34.0
	check(Advisor.goal_met(g3[0], v), "at the floor it is")
	eq(a.goals(4)[1]["title"], "Keep your speed above 60%.", "a share reads as a percent")
	# a damaged_blocks goal is met at or below its number
	var g6: Dictionary = a.goals(6).filter(func(g): return g["id"] == "s6_repair")[0]
	check(Advisor.goal_met(g6, {"damaged_blocks": 0}) and not Advisor.goal_met(g6, {"damaged_blocks": 2}), "damaged_blocks counts down")
	# without the numbers: the power clause is skipped, the goals that are all numbers of the file are dropped
	var bare := Advisor.new({}, {})
	eq(bare.goals(3), [], "stage 3 is all the balance track's numbers")
	var g2 := bare.goals(2)
	eq(g2.map(func(g): return g["id"]), ["s2_fab", "s2_arms", "s2_speed", "s2_toll"], "stage 2 loses its blueprint goal")
	eq(g2[1]["alts"][0].map(func(c): return c["key"]), ["guns", "layers"], "and its power clause")
	eq(bare.goals(1).size(), 5, "stage 1 is untouched")


func test_the_card_shows_what_the_setting_allows() -> void:
	var a := _advisor()
	a.values = {"intakes": 0, "guns": 0, "layers": 0, "medbays": 0, "fuel_margin": -3.0, "credits_over_toll": -10.0}
	a.stage = 1
	a.warning = {"id": "fuel", "text": a.warning_text("fuel"), "left": 10.0}
	a.mode_now = "full"
	var c: Dictionary = a.card()
	eq(c["goal"]["id"], "s1_intake", "Full: the goal")
	eq(c["warning"]["id"], "fuel", "Full: and the warning")
	a.mode_now = "warn"
	c = a.card()
	check(not c.has("goal"), "Warnings only: no goal")
	eq(c["warning"]["id"], "fuel", "Warnings only: the warning")
	a.mode_now = "off"
	eq(a.card(), {}, "Off: nothing")
	a.mode_now = "full"
	a.warning = {}
	a.values = {"intakes": 1, "guns": 3, "layers": 1, "medbays": 1, "fuel_margin": 3.0, "credits_over_toll": 5.0}
	check(a.card()["done"], "every goal met: the card says the list is done")
	a.stage = 9
	eq(a.card(), {}, "the ending region has no list")


# --- tips ----------------------------------------------------------------------------------------------------

func test_a_tip_shows_once_per_profile_and_survives_a_save() -> void:
	_clean()
	var p := Profile.new(TMP)
	var a := _advisor()
	a.profile = p
	a.queue_tips(["first_fight"])
	eq(a.next_tip(), "first_fight", "the first fight's tip waits")
	a.queue_tips(["first_fight"])
	eq(a.tip_queue.size(), 1, "it is not queued twice")
	a.tip_shown("first_fight")
	check(p.has_tip("first_fight"), "shown: the profile has it")
	eq(a.next_tip(), "", "and the queue is empty")
	a.queue_tips(["first_fight", "first_station"])
	eq(a.tip_queue, ["first_station"], "a tip the profile has is not shown again, a new one is")
	var q := Profile.new(TMP)  # a new session
	check(q.has_tip("first_fight"), "the tip survives a save")
	eq(q.tips.keys(), ["first_fight"], "and only the shown one is listed")
	var b := _advisor()
	b.profile = q
	b.queue_tips(["first_fight"])
	eq(b.next_tip(), "", "a new Advisor on the saved profile does not show it again")
	_clean()


func test_the_tips_wait_for_their_moment() -> void:
	var ship := _built()
	var c := _campaign()
	var a := _advisor()
	eq(a.watch(ship, c, {}), [], "nothing has happened")
	eq(a.watch(ship, c, {"build_on": true}), ["first_build"], "build mode")
	eq(a.watch(ship, c, {"fighting": true, "breach": true}), ["first_fight", "first_breach"], "a fight with a breach")
	eq(a.watch(ship, c, {"station": true, "craft": true, "shields": true, "loadout": true, "rig_bonus": true}),
		["first_station", "first_fabricator", "first_shields", "first_boarding", "first_rig_bonus"], "the screens")
	ship.crafting.unlock("assembly_rig")
	eq(a.watch(ship, c, {}), ["first_blueprint"], "a blueprint learned since the last look")
	eq(a.watch(ship, c, {}), [], "once")
	ship.crew.append(CrewMember.from_character(Characters.ids()[0], Vector2(10, 18)))
	eq(a.watch(ship, c, {}), ["first_crew"], "a crewmate hired since the last look")
	ship.components.wrecks.append({"id": "laser_mk1", "cells": [Vector2i(9, 16)]})
	eq(a.watch(ship, c, {}), ["first_wreck"], "a wrecked part")
	ship.components.wrecks.clear()
	c.current = c.drift.exit_id()
	eq(a.watch(ship, c, {}), ["first_warden"], "the warden at the beacon")
	c.last_jump = {"ok": true, "drift": true}
	check(a.watch(ship, c, {}).has("first_drift_jump"), "a drift jump")
	ship.inventory.load_dict({"fuel": 1})
	c.jumps = 3
	a.values = {"fuel": 1}
	check(a.watch(ship, c, {}).has("low_fuel"), "low fuel")
	ship.inventory.add("spotter_cam_mk1", 1)
	check(a.watch(ship, c, {}).has("first_mod"), "a mod in the hold")
	# a look that begins a run (or a load) fires nothing that waits for a change
	var fresh := _advisor()
	var f := fresh.watch(ship, c, {})
	check(not f.has("first_blueprint") and not f.has("first_crew"), "the first look has nothing to compare with")


# --- warnings ------------------------------------------------------------------------------------------------

func test_a_warning_fires_once_a_stage_unless_it_gets_worse() -> void:
	var a := _advisor()
	var v := {"stage": 2, "margin": -2.0}
	var conds := a.conditions(v)
	eq(conds.map(func(c): return c["id"]), ["power"], "demand over supply")
	eq(a.fire(conds, 2), "power", "it fires")
	eq(a.warning["id"], "power", "and is on the card")
	eq(a.fire(conds, 2), "", "not twice in the stage")
	v["margin"] = -2.8
	eq(a.fire(a.conditions(v), 2), "", "a little worse is not worse enough")
	v["margin"] = -3.0
	eq(a.fire(a.conditions(v), 2), "power", "a wide margin worse (x1.5) fires again")
	v["margin"] = -3.5
	eq(a.fire(a.conditions(v), 2), "", "and the new level is the one to beat")
	v["margin"] = -2.0
	eq(a.fire(a.conditions(v), 3), "power", "the next stage starts afresh")
	check(a.warned["power"]["stage"] == 3, "remembered at its stage")
	var ev := a.take_events()
	eq(ev.filter(func(e): return e["type"] == "warning").size(), 3, "three warnings were said")


func test_every_warning_has_its_trigger() -> void:
	var a := _advisor()
	var base := {"stage": 3, "power": 40.0, "margin": 2.0, "accel_ratio": 0.9, "credits": 500, "credits_over_toll": 200, "scrap": 100, "known": 30, "fuel": 8,
		"fuel_margin": 4.0, "hops": 5, "station_hops": 1, "structure": 0.9, "at_exit": false, "warden_up": false}
	eq(a.conditions(base), [], "a healthy ship says nothing")
	var tests := {
		"outgunned": {"at_exit": true, "warden_up": true, "power": 30.0, "credits_over_toll": -5, "hops": 0},  # under 0.8 x the warden's 45 = 36 and short of the toll
		"fuel": {"fuel_margin": -2.0},
		"toll": {"hops": 2, "warden_up": true, "credits_over_toll": 10, "scrap": 700},  # inside two jumps, under the 40 over the toll, scrap to sell
		"hull": {"structure": 0.4, "station_hops": 4},
		"cliff": {"power": 35.0},  # entering stage 3 under 36
		"power": {"margin": -1.0},
		"mass": {"accel_ratio": 0.5},
		"scrap": {"scrap": 1600, "credits": 100},
		"blueprints": {"stage": 5, "known": 24},
	}
	for id in tests:
		var v := base.duplicate()
		v.merge(tests[id], true)
		var ids: Array = a.conditions(v).map(func(c): return c["id"])
		check(ids.has(id), "%s warns: %s" % [id, str(ids)])
	var skull := a.conditions(base, {"foe_ratio": 1.7})
	eq(skull.map(func(c): return c["id"]), ["skulls"], "a four skull enemy (1.6 and over) in a fight")
	eq(a.conditions(base, {"foe_ratio": 1.2}), [], "a harder one than yours but under four skulls is not worth a warning")
	# the stage 3 cliff is only the stage 3 cliff, and toll, hull and the rest need their numbers
	var v2 := base.duplicate()
	v2["power"] = 35.0
	v2["stage"] = 4
	check(not a.conditions(v2).any(func(c): return c["id"] == "cliff"), "no cliff in stage 4")
	var none := Advisor.new({}, {})
	check(none.conditions({"stage": 3, "power": 1.0, "accel_ratio": 0.1, "scrap": 9999, "credits": 0, "known": 1, "structure": 0.1, "station_hops": 9, "margin": 1.0}).is_empty(), "no numbers, no numbers-based warnings")
	check(not none.conditions({"stage": 3, "margin": -1.0}).is_empty(), "but a power shortfall needs none")


# --- the setting and the question --------------------------------------------------------------------------------

func test_each_setting_hides_what_it_should() -> void:
	var ship := _built()
	var c := _campaign()
	ship.inventory.load_dict({"fuel": 0})
	for mode in ["full", "warn", "off"]:
		var a := _advisor()
		a.mode_now = mode
		a.update(ship, c, {"fighting": true})  # a fight tip is due, and the empty tank is a warning
		var ev := a.take_events().map(func(e): return e["type"])
		eq(a.shows("card"), mode == "full", "%s: the card" % mode)
		eq(a.shows("tips"), mode == "full", "%s: the tips" % mode)
		eq(a.shows("warnings"), mode != "off", "%s: the warnings" % mode)
		eq(a.next_tip() == "first_fight", mode == "full", "%s: the first fight's tip is queued only in Full" % mode)
		eq(ev.has("warning"), mode != "off", "%s: the warning is said unless Off" % mode)
		eq(ev.has("goal"), mode == "full" and ev.has("goal"), "%s: goals tick only in Full" % mode)
		eq(a.card().has("goal"), mode == "full", "%s: the goal on the card" % mode)
		eq(a.card().has("warning"), mode != "off", "%s: the warning on the card" % mode)
		if mode == "off":
			eq(a.card(), {}, "Off: the card has nothing")
			eq(ev, [], "Off: nothing happens")


func test_a_tip_hidden_by_the_setting_is_not_used_up() -> void:
	_clean()
	var p := Profile.new(TMP)
	p.set_ledger("warn")
	var a := _advisor()
	a.profile = p
	a.queue_tips(["first_fight"])
	eq(a.next_tip(), "", "Warnings only: no tip")
	check(not p.has_tip("first_fight"), "and it is not marked as seen")
	p.set_ledger("full")
	a.queue_tips(["first_fight"])
	eq(a.next_tip(), "first_fight", "switched to Full: it still shows the next time")
	_clean()


func test_the_first_run_prompt_shows_once() -> void:
	_clean()
	var p := Profile.new(TMP)
	eq(p.ledger, "full", "a new profile is Full")
	check(not p.ledger_ask_due(), "no run has ended: no question yet")
	p.add_run({"ship": "Courier", "jumps": 3})
	check(p.ledger_ask_due(), "a run has ended: ask")
	p.mark_ledger_asked()
	check(not p.ledger_ask_due(), "asked: not again")
	var q := Profile.new(TMP)
	check(q.ledger_asked and not q.ledger_ask_due(), "and it is remembered")
	q.ledger_asked = false
	q.set_ledger("off")
	check(not q.ledger_ask_due(), "a Ledger that is already off is not asked about")
	check(not q.set_ledger("loud") and q.ledger == "off", "an unknown setting is refused")
	_clean()


func test_the_profile_keeps_the_ledger_and_loads_an_older_file_as_full() -> void:
	_clean()
	var p := Profile.new(TMP)
	p.set_ledger("warn")
	p.mark_tip("first_build")
	p.mark_tip("first_fight")
	p.ledger_run = {"seed": 7, "jumps": 3, "base": {"accel": 12.5, "plates": 2}, "warned": {"fuel": {"stage": 1, "level": 2.0}}, "announced": ["1:s1_intake"]}
	p.save()
	var q := Profile.new(TMP)
	eq([q.ledger, q.tips.keys()], ["warn", ["first_build", "first_fight"]], "the setting and the tips, in the order shown")
	eq(int(q.ledger_run["seed"]), 7, "the run it follows")
	eq(Profile.VERSION, 6, "version 6")
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 5, "hints": {}, "runs": [{"ship": "Courier"}], "sound": {"master": 0.5}}))
	f.close()
	var old := Profile.new(TMP)
	eq([old.ledger, old.tips, old.ledger_asked, old.ledger_run], ["full", {}, false, {}], "a version 5 file loads as Full with nothing seen")
	check(old.ledger_ask_due(), "and has a run behind it, so the question is due")
	_clean()


func test_the_run_the_ledger_follows_survives_a_continue() -> void:
	_clean()
	var ship := _built()
	var c := _campaign(11)
	var p := Profile.new(TMP)
	var a := _advisor()
	a.profile = p
	a.update(ship, c, {})
	check(a.base.has("accel") and a.dirty, "a new run: its start is measured")
	var st := a.state()
	eq(int(st["seed"]), 11, "the run's seed")
	a.warned["blueprints"] = {"stage": 1, "level": 1.0}
	p.ledger_run = a.state()
	p.save()
	var q := Profile.new(TMP)
	var b := _advisor()
	b.profile = q
	var c2 := _campaign(11)  # a Continue: the same run
	b.update(ship, c2, {})
	eq([float(b.base["accel"]), float(b.base["plates"])], [float(a.base["accel"]), float(a.base["plates"])], "a Continue keeps the start the speed is measured against")
	check(b.warned.has("blueprints"), "and the warnings already given this stage")
	var other := _advisor()
	other.profile = q
	other.update(ship, _campaign(12), {})
	check(not other.warned.has("blueprints"), "another run starts afresh")
	_clean()


# --- the words -----------------------------------------------------------------------------------------------

func test_advisor_json_validates() -> void:
	var w := Advisor.load_words()
	var vocab: Array = Advisor.VOCAB
	var kws: Dictionary = w["keywords"]
	var ids := {}
	for s in range(1, 9):
		var goals: Array = w["stages"].get(str(s), [])
		check(goals.size() >= 3 and goals.size() <= 5, "stage %d has three to five goals (%d)" % [s, goals.size()])
		for g in goals:
			check(not ids.has(g["id"]), "goal id %s is unique" % g["id"])
			ids[g["id"]] = true
			check(str(g["title"]).length() <= 60 and str(g["why"]).length() <= 120 and str(g["title"]) != "" and str(g["why"]) != "", "%s: a short title and a short why" % g["id"])
			var alts: Array = g["check"] if g["check"] is Array else [g["check"]]
			var first_keys := []
			for alt in alts:
				check(alt is Dictionary and not alt.is_empty(), "%s: a check is clauses" % g["id"])
				for k in alt:
					check(vocab.has(k), "%s: check key %s is in the vocabulary" % [g["id"], k])
					var val = alt[k]
					if val is String:
						check(val.begins_with("p:") and Advisor.STAGE_KEYS.has(val.substr(2)), "%s: %s is a p: key of the progression format" % [g["id"], str(val)])
					else:
						check(val is float or val is int, "%s: %s is a number" % [g["id"], k])
					if first_keys.is_empty() or alts.size() == 1:
						first_keys.append(k)
			var text := str(g["title"]) + " " + str(g["why"])
			for m in _marks(text):
				if m.begins_with("="):
					check(first_keys.has(m.substr(1)), "%s: the hole {%s} is a key of its check" % [g["id"], m])
				else:
					check(kws.has(m.get_slice(":", 0)), "%s: keyword %s exists" % [g["id"], m])
	check(not w["stages"].has("9"), "the ending region has no list")
	var tips: Array = w["tips"]
	eq(tips.map(func(t): return t["id"]), Advisor.TIPS, "the tips are the ones advisor.gd waits for, in order")
	check(tips.size() >= 14 and tips.size() <= 16, "about fifteen tips")
	for t in tips:
		check(str(t["title"]) != "" and str(t["text"]).length() > 20 and str(t["text"]).length() <= 130, "tip %s is one short line (%d)" % [t["id"], str(t["text"]).length()])
		for m in _marks(str(t["text"])):
			check(kws.has(m.get_slice(":", 0)), "tip %s: keyword %s exists" % [t["id"], m])
	var warns: Dictionary = w["warnings"]
	var wids := warns.keys()
	wids.sort()
	var want: Array = Advisor.WARNINGS.duplicate()
	want.sort()
	eq(wids, want, "a line for every warning, and no other")
	for id in warns:
		check(str(warns[id]["text"]).length() > 20 and str(warns[id]["text"]).length() <= 130, "warning %s is one short line" % id)
	for k in vocab:
		check(w["labels"].has(k), "the progress names %s" % k)
	for k in ["worse", "toll_jumps", "toll_scrap", "scrap_credits", "hull_stations", "warn_s", "pace_s", "low_fuel"]:
		check(w["rules"].has(k), "rule " + k)
	check(float(w["rules"]["worse"]) > 1.0, "worse is a factor over 1")
	for k in kws:
		check(str(kws[k]["hover"]).split(" ", false).size() <= 12, "keyword %s: a hover line of 12 words at most" % k)


## The marks of a text: what is between { and } ("=guns", "intake", "gun:guns").
func _marks(text: String) -> Array:
	var out := []
	var rest := text
	while rest.contains("{"):
		var a := rest.find("{")
		var b := rest.find("}", a)
		check(b > a, "a mark is closed: " + text)
		if b <= a:
			break
		out.append(rest.substr(a + 1, b - a - 1))
		rest = rest.substr(b + 1)
	return out


func test_the_keywords_have_their_own_colours() -> void:
	var kws: Dictionary = Advisor.load_words()["keywords"]
	var theirs: Dictionary = Content.read("res://data/describe.json")["keywords"]
	var ids := kws.keys()
	for i in ids.size():
		var c := Color(str(kws[ids[i]]["color"]))
		check(_contrast(c, PANEL) >= 4.5, "%s reads on the dark panels (%.2f)" % [ids[i], _contrast(c, PANEL)])
		for line in LINE_COLS:
			check(_lab(c).distance_to(_lab(line)) >= 15.0, "%s differs from the line colours" % ids[i])
		for j in range(i + 1, ids.size()):
			check(_lab(c).distance_to(_lab(Color(str(kws[ids[j]]["color"])))) >= 15.0, "%s and %s differ" % [ids[i], ids[j]])
		for k in theirs:
			if k == ids[i]:  # the same mechanic keeps the same colour as on the part cards
				eq(Color(str(theirs[k]["color"])), c, "%s is the colour the part cards use" % k)
			else:
				check(_lab(c).distance_to(_lab(Color(str(theirs[k]["color"])))) >= 15.0, "%s differs from the part keyword %s" % [ids[i], k])


func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _lab(c: Color) -> Vector3:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	var r: float = f.call(c.r)
	var g: float = f.call(c.g)
	var b: float = f.call(c.b)
	var x := (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	var y := 0.2126 * r + 0.7152 * g + 0.0722 * b
	var z := (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	var t := func(v: float) -> float: return pow(v, 1.0 / 3.0) if v > 0.008856 else 7.787 * v + 16.0 / 116.0
	var fx: float = t.call(x)
	var fy: float = t.call(y)
	var fz: float = t.call(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


func test_keyword_marks_become_runs() -> void:
	eq(Advisor.segments("Mount your {intake}."), [{"text": "Mount your ", "kw": ""}, {"text": "intake", "kw": "intake"}, {"text": ".", "kw": ""}], "a mark is its own word")
	eq(Advisor.segments("Fit three {gun:guns} now"), [{"text": "Fit three ", "kw": ""}, {"text": "guns", "kw": "gun"}, {"text": " now", "kw": ""}], "{id:words} shows its words")
	eq(Advisor.plain("A {shield} or a {medbay}."), "A shield or a medbay.", "plain text has the marks taken out")
	eq(Advisor.segments("no marks"), [{"text": "no marks", "kw": ""}], "plain text is one run")
	var k := _advisor().keyword("intake")
	check(k["color"] is Color and str(k["hover"]) != "", "a keyword has a colour and a hover line")
	eq(_advisor().keyword("nothing"), {}, "an unknown keyword is {}")


func test_the_numbers_format_is_checked_and_the_fixture_follows_it() -> void:
	eq(Advisor.numbers_problems(_numbers()), [], "the fixture is in the format the balance track writes")
	var bad := _numbers()
	bad["stages"]["3"].erase("plates")
	bad["warn"].erase("cliff_power")
	bad["stages"].erase("8")
	var probs := Advisor.numbers_problems(bad)
	eq(probs.size(), 3, "a missing stage, key and warn key are all found: " + str(probs))
	if FileAccess.file_exists(Advisor.NUMBERS_PATH):  # once the balance track's file is in the game it has to be sound too
		eq(Advisor.numbers_problems(Advisor.load_numbers()), [], "data/progression.json is in the format")
	for s in range(1, 9):  # the fixture's stages climb: more guns and layers, never fewer
		if s > 1:
			check(_numbers()["stages"][str(s)]["guns"] >= _numbers()["stages"][str(s - 1)]["guns"], "stage %d has no fewer guns" % s)


# --- it only reads ---------------------------------------------------------------------------------------------

## A seeded run of 120 seconds in the start sector: the sector ticks, the debris spawns and is hauled, and the campaign's own clock runs;
## `with_advisor` looks at the ship every 0.1 s as the card would. Returns everything that makes up the game's state as one text.
func _run(with_advisor: bool) -> String:
	var ship := _built()
	ship.inventory.load_dict({"fuel": 4, "credits": 60, "scrap": 700})
	var c := _campaign(21)
	var sector = c.sector_at(c.current)
	sector.enter()
	sector.set_flight(ship)
	var debris = DriftDebris.for_sector(sector, 21)
	var a := _advisor()
	a.mode_now = "full"
	for i in 1200:
		sector.tick(0.1, ship)
		debris.step(ship, 0.1)
		if with_advisor:
			a.tick(0.1, ship, c, {"build_on": i % 7 == 0, "fighting": i % 50 == 3})
			a.take_events()
			a.next_tip()
	var state := {"campaign": c.to_dict(), "ship": ship.to_dict(), "campaign_rng": c.rng.state, "sector_rng": sector.rng.state, "debris_rng": debris.rng.state,
		"debris": debris.pieces.size(), "clock": sector.clock}
	return JSON.stringify(state)


func test_the_advisor_never_changes_the_state_or_the_rng() -> void:
	var off := _run(false)
	var on := _run(true)
	check(off.length() > 1000, "the run left a state to compare")
	check(on == off, "the same seeded run, with the Ledger looking every tenth of a second and without it, ends in the same state")
	# a single look changes neither the campaign nor the ship, nor draws from the campaign's rng
	var ship := _built()
	var c := _campaign(33)
	var before := JSON.stringify({"c": c.to_dict(), "s": ship.to_dict(), "r": c.rng.state})
	var a := _advisor()
	a.update(ship, c, {})
	a.update(ship, c, {"fighting": true, "foe_ratio": 2.0})
	eq(JSON.stringify({"c": c.to_dict(), "s": ship.to_dict(), "r": c.rng.state}), before, "one look leaves the campaign, the ship and the rng as they were")


func test_a_look_is_at_most_once_a_second() -> void:
	var ship := _built()
	var c := _campaign()
	var a := _advisor()
	a.tick(0.4, ship, c)
	check(a.values.is_empty(), "0.4 s: no look yet")
	a.tick(0.4, ship, c)
	check(a.values.is_empty(), "0.8 s: not yet")
	a.tick(0.4, ship, c)
	check(not a.values.is_empty(), "1.2 s: it looked")
	var seen: Dictionary = a.values
	ship.inventory.add("credits", 77)
	a.tick(0.5, ship, c)
	check(a.values == seen, "and not again half a second later")
	a.tick(0.6, ship, c)
	check(int(a.values["credits"]) == 77, "but a second after the last look it did")


func test_a_goal_met_ticks_once() -> void:
	var ship := _built()
	var c := _campaign()
	var a := _advisor()
	a.update(ship, c, {})
	var met := a.take_events().filter(func(e): return e["type"] == "goal").map(func(e): return e["id"])
	check(met.has("s1_intake") and met.has("s1_guns") and met.has("s1_cover"), "the goals the ship already meets tick at the first look: " + str(met))
	a.update(ship, c, {})
	eq(a.take_events().filter(func(e): return e["type"] == "goal"), [], "and not again")
	# a goal lost and met again does not tick twice
	ship.components.instances.erase(ship.components.instances.keys()[3])  # the net mouth goes
	ship.refresh()
	a.update(ship, c, {})
	check(a.values["intakes"] == 0, "the intake is gone")
	a.take_events()
	var again := _built()
	a.update(again, c, {})
	eq(a.take_events().filter(func(e): return e["type"] == "goal" and e["id"] == "s1_intake"), [], "the tick for the intake was already given")
