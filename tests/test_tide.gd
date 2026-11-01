extends "res://tests/base_test.gd"
## The Hollow tide (scripts/space/tide.gd, docs/MECHANICS_REVIEW.md P1): the front along the map, which places fall and
## which hold, the steps until a place falls, the linger clock and its warnings, the campaign's hooks (jumps, waits and
## tows push it, a Hollow place sends a hollow event and ghost ships, saves), the map view's tooltip, status and clock
## line, and the six hollow events of the mech_tide pack.

const Campaign = preload("res://scripts/space/campaign.gd")
const Content = preload("res://scripts/data/content.gd")
const Drift = preload("res://scripts/space/drift.gd")
const Events = preload("res://scripts/space/events.gd")
const Tide = preload("res://scripts/space/tide.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const TideHud = preload("res://scripts/ui/tide_hud.gd")
const Salvage = preload("res://scripts/space/salvage.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
## A small config with round numbers: the front moves 100 px a step after 2 steps of grace on the 1000 px test map.
const CFG := {"grace": 2, "jumps_to_cross": 10, "linger_s": 240, "linger_warn": [60, 15]}


class FakeCombat extends Node:
	var active := false


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


## A 6-node map along x: a (station, the entry) 0 px, b 100, c 250, d (station) 400, e 700, f 1000.
func _line_map(extra := {}) -> Drift:
	var nodes := []
	for spec in [["a", "station", 100], ["b", "pirate", 200], ["c", "wreck_field", 350], ["d", "station", 500], ["e", "distress", 800], ["f", "gate", 1100]]:
		var n := {"id": spec[0], "name": "", "type": spec[1], "place": "", "faction": "", "hidden_until": "", "start": spec[0] == "a", "clan": false, "pos": [spec[2], 300 + 40 * nodes.size()]}
		n.merge(extra.get(spec[0], {}), true)
		nodes.append(n)
	return Drift.from_dict({"nodes": nodes, "lanes": []})


func _line_tide(exit_id := "", stage := 1) -> Tide:
	return Tide.make(_line_map(), "a", CFG, exit_id, stage)


# --- the front ---------------------------------------------------------------------------------------------

func test_the_front_moves_one_step_of_the_axis_per_jump_after_the_grace() -> void:
	var t := _line_tide()
	eq(t.axis_len, 1000.0, "the axis is the farthest node's px from the entry")
	eq(t.per_step(), 100.0, "1000 px over 10 jumps")
	eq(t.front(), 0.0, "at the start the front has not moved")
	t.advance(2)
	eq(t.front(), 0.0, "the grace holds it")
	for i in 5:
		t.advance(1)
		eq(t.front(), 100.0 * (i + 1), "step %d after the grace" % (i + 1))
	t.advance(-100)
	eq([t.steps, t.front()], [0, 0.0], "never below 0")


func test_the_real_map_front_is_deterministic_and_matches_the_data() -> void:
	var cfg := Tide.config()
	eq([int(cfg["grace"]), int(cfg["jumps_to_cross"]), int(cfg["linger_s"])], [3, 16, 240], "data/tide.json")
	eq(cfg["linger_warn"].map(func(v): return int(v)), [60, 15], "the warnings")
	eq(cfg["stage_jumps_to_cross"].map(func(v): return int(v)), [16, 14, 13, 12, 12, 11, 11, 10], "the stage table")
	var a := Campaign.new(21)
	var b := Campaign.new(21)
	var rusthold: Vector2 = a.drift.node("rusthold")["pos"]
	var far := 0.0
	for n in a.drift.nodes:
		far = maxf(far, n["pos"].x - rusthold.x)
	eq(a.tide.axis_len, far, "the axis is the farthest node's projection from Rusthold")
	for s in [0, 3, 4, 10, 19, 25]:
		a.tide.steps = s
		b.tide.steps = s
		eq(a.tide.front(), b.tide.front(), "the same seed, the same front at step %d" % s)
		check(is_equal_approx(a.tide.front(), maxf(s - 3, 0) * far / 16.0), "step %d: (steps - grace) * axis / 16" % s)


func test_stage_picks_the_jumps_to_cross() -> void:
	var cfg := {"grace": 0, "jumps_to_cross": 16, "linger_s": 240, "linger_warn": [60, 15], "stage_jumps_to_cross": [16, 14, 13]}
	var map := _line_map()
	eq(Tide.make(map, "a", cfg).jumps_to_cross, 16, "stage 1")
	eq(Tide.make(map, "a", cfg, "", 2).jumps_to_cross, 14, "stage 2")
	eq(Tide.make(map, "a", cfg, "", 3).jumps_to_cross, 13, "stage 3")
	eq(Tide.make(map, "a", cfg, "", 9).jumps_to_cross, 16, "past the table: the default")


# --- who falls ---------------------------------------------------------------------------------------------

func test_nodes_fall_in_order_of_their_projection_and_stations_hold() -> void:
	var t := _line_tide()
	var order := []
	for s in 14:
		t.steps = s
		for id in ["b", "c", "e", "f"]:
			if t.is_hollow(id) and not order.has(id):
				order.append(id)
		check(not t.is_hollow("a") and not t.is_hollow("d"), "step %d: the stations hold" % s)
	eq(order, ["b", "c", "e", "f"], "nearest the entry first")
	t.steps = 3
	check(t.is_hollow("b") and not t.is_hollow("c"), "the front at 100 px takes b (100) and not c (250)")
	t.steps = 99
	check(not t.is_hollow("a") and not t.is_hollow("d") and t.is_hollow("f"), "even at the end only the stations hold")
	check(not t.is_hollow("nowhere"), "an unknown node never falls")
	eq(t.hollow_count(), 4, "four places fell")
	t.steps = 0
	eq(t.hollow_count(), 0, "none at the start")


func test_the_exit_holds_too() -> void:
	var t := _line_tide("e")
	t.steps = 99
	check(not t.is_hollow("e") and t.is_hollow("f") and t.is_hollow("b"), "the exit beacon holds, others fall")
	eq(t.jumps_until("e"), -1, "it never falls")


func test_jumps_until() -> void:
	var t := _line_tide()
	eq([t.jumps_until("b"), t.jumps_until("c"), t.jumps_until("e"), t.jumps_until("f")], [3, 5, 9, 12], "from step 0")
	eq([t.jumps_until("a"), t.jumps_until("d"), t.jumps_until("nowhere")], [-1, -1, -1], "stations and unknown nodes never fall")
	t.advance(1)
	eq(t.jumps_until("b"), 2, "one step on")
	t.advance(2)
	eq([t.jumps_until("b"), t.jumps_until("c")], [0, 2], "b is Hollow now, c is two off")
	for s in 14:
		t.steps = s
		for id in ["b", "c", "e", "f"]:
			var n := t.jumps_until(id)
			check((n == 0) == t.is_hollow(id), "step %d, %s: 0 means Hollow now" % [s, id])
			if n > 0:
				t.steps = s + n - 1
				check(not t.is_hollow(id), "step %d, %s: one step before it is still free" % [s, id])
				t.steps = s + n
				check(t.is_hollow(id), "step %d, %s: after %d it has fallen" % [s, id, n])
				t.steps = s


func test_advance_says_how_many_places_it_took() -> void:
	var t := _line_tide()
	eq(t.advance(2), 0, "the grace takes nothing")
	eq(t.advance(1), 1, "b")
	eq(t.advance(2), 1, "c, then nothing new")
	eq(t.advance(100), 2, "e and f")


# --- lingering ---------------------------------------------------------------------------------------------

func test_240_seconds_of_lingering_is_one_step_with_one_warning_each() -> void:
	var t := _line_tide()
	var lines := []
	for i in 239:
		lines.append_array(t.linger(1.0))
	eq(t.steps, 0, "239 s: no step yet")
	eq(lines, ["The tide rises in 60 s", "The tide rises in 15 s"], "each warning once, at the right time")
	lines = t.linger(1.0)
	eq(lines, [Tide.RISES_TEXT], "the 240th second raises the tide")
	eq([t.steps, t.linger_t], [1, 0.0], "one step, the clock starts again")
	lines = []
	for i in 240:
		lines.append_array(t.linger(1.0))
	eq(lines, ["The tide rises in 60 s", "The tide rises in 15 s", Tide.RISES_TEXT], "the next period warns again")
	eq(t.steps, 2, "two steps")


func test_lingering_starts_over_on_arrival_and_carries_a_long_frame() -> void:
	var t := _line_tide()
	t.linger(200.0)
	eq(Tide.clock(t.linger_left()), "0:40", "40 s left")
	t.reset_linger()
	eq(t.linger_left(), 240.0, "arriving starts the count again")
	var lines := t.linger(250.0)  # one long frame: the rise, with the spare seconds counted towards the next
	eq(t.steps, 1, "one step")
	eq(lines, [Tide.RISES_TEXT], "no warnings of a period that was skipped over")
	eq(t.linger_t, 10.0, "10 s are already into the next period")
	eq(t.linger(0.0), [], "no time, no lines")
	eq(t.linger(-5.0), [], "time does not run backwards")


func test_lingering_stops_once_the_tide_has_crossed_the_map() -> void:
	var t := _line_tide()
	t.steps = 99
	check(t.spent(), "nothing is left to take")
	eq(t.linger(1000.0), [], "so it does not rise")
	eq(t.steps, 99, "and does not count")


func test_clock_text() -> void:
	eq([Tide.clock(240.0), Tide.clock(161.2), Tide.clock(59.0), Tide.clock(0.2), Tide.clock(0.0), Tide.clock(-3.0)], ["4:00", "2:42", "0:59", "0:01", "0:00", "0:00"], "M:SS, rounded up")


# --- the campaign ------------------------------------------------------------------------------------------

func test_lingering_never_moves_the_jump_counter_or_the_debt() -> void:
	var c := Campaign.new(5)
	var debt := c.debt
	var lines := []
	for i in 481:
		lines.append_array(c.linger(1.0))
	eq(c.tide.steps, 2, "two steps in 481 s")
	eq([c.jumps, c.debt, c.paid, c.behind()], [0, debt, 0, 0], "no jump, no debt, nothing owed")
	check(lines.has(Tide.RISES_TEXT), "the HUD gets the line")


func test_a_jump_a_wait_and_a_tow_each_advance_the_tide() -> void:
	var ship := _ship()
	var c := Campaign.new(8)
	var to := ""
	for o in c.neighbours(c.current):
		if c.node(o)["type"] != "gate":
			to = o
			break
	check(_jump(c, to, ship)["ok"], "a jump")
	eq([c.tide.steps, c.jumps], [1, 1], "pushed the tide one step")
	ship.inventory.counts.erase("fuel")
	check(c.wait(ship)["ok"], "a wait")
	eq([c.tide.steps, c.jumps], [2, 2], "pushed it again")
	check(c.tow(ship)["ok"], "a tow")
	eq([c.tide.steps, c.jumps], [3, 3], "and again")
	eq(c.current, "rusthold", "home")


func test_the_note_says_how_many_places_fell() -> void:
	var ship := _ship()
	var c := Campaign.new(8)
	ship.inventory.add("fuel", 50)
	var said := []
	var guard := 0
	while c.tide.steps < 12 and guard < 40:
		guard += 1
		var to := ""
		for o in c.neighbours(c.current):
			if c.node(o)["type"] != "gate":
				to = o
				break
		var r := _jump(c, to, ship)
		check(r["ok"], "jump %d: %s" % [guard, r["why"]])
		for line in r["notes"]:
			if str(line).begins_with("The Hollow takes"):
				said.append(line)
	check(not said.is_empty(), "the front fell on some places between steps 4 and 12")
	for line in said:
		check(line == "The Hollow takes 1 more place." or line.ends_with(" more places."), "a note: " + line)


func test_a_hollow_place_sends_a_hollow_event_and_a_station_docks_as_usual() -> void:
	var ship := _ship()
	var c := Campaign.new(3)
	c.tide.steps = 40
	var node := ""
	for n in c.drift.nodes:
		if n["type"] in ["pirate", "wreck_field", "distress", "asteroid_field", "empty"]:
			node = n["id"]
			break
	check(c.is_hollow(node), "the far side has fallen")
	c.current = node
	var a := c.arrive(ship)
	eq(a["event"].get("type", ""), "hollow", "a hollow event instead of the node's own")
	check(str(a["event"].get("id", "")).begins_with("hollow_"), "one of the pack's: " + str(a["event"].get("id", "")))
	check(c.events_seen >= 1, "it counts as an event met")
	c.current = "rusthold"
	check(not c.is_hollow("rusthold"), "Rusthold holds")
	a = c.arrive(ship)
	eq(a["refused"], "", "the dock master lets you in")
	check(a["event"].get("type", "") != "hollow", "its own greeting, not a ghost")
	check(c.flags.has("at_rusthold"), "docked")
	check(c.dock_block("rusthold") == "" and not c.station_cfg("rusthold").is_empty(), "and the menu is there")


func test_no_hollow_event_falls_back_to_a_fight() -> void:
	var ship := _ship()
	var c := Campaign.new(3, {}, Events.new("res://tests"))  # no *.json there, so no events at all
	c.tide.steps = 40
	for n in c.drift.nodes:
		if n["type"] == "pirate" or n["type"] == "wreck_field" or n["type"] == "distress":
			c.current = n["id"]
			break
	eq(c.arrive(ship)["event"].get("id", ""), "hollow_hostile", "the built-in fight")
	eq(Campaign.HOSTILE_HOLLOW["choices"][0]["outcomes"][0]["effects"], {"fight": "tier"}, "which is a fight")


func test_hollow_places_send_ghost_ships_and_have_no_trade() -> void:
	var c := Campaign.new(3)
	for t in ["1", "2", "3"]:
		eq(c.cfg["enemies"]["hollow"][t], ["gen:hollow"], "the hollow table builds ghost ships (shipgen's hollow faction), tier " + t)
	check(c.fight_path("tier", "hollow").begins_with("gen:hollow:"), "fight_path(tier, hollow) rolls a generated ghost")
	var other := ""
	for n in c.drift.nodes:
		if n["type"] == "pirate":
			other = n["id"]
			break
	c.current = other
	c.tide.steps = 0
	check(not c.fight_path("tier", "pirate").begins_with("gen:hollow:"), "a free place sends its own")
	c.tide.steps = 40
	check(c.fight_path("tier", "pirate").begins_with("gen:hollow:"), "a Hollow place sends ghosts whatever it was")
	var trader := ""
	for seed_value in 60:
		var d := Campaign.new(seed_value)
		for n in d.drift.nodes:
			if n["clan"]:
				trader = n["id"]
				c = d
				break
		if trader != "":
			break
	check(trader != "", "some seed has a Scrapper trader")
	c.tide.steps = 0
	check(not c.station_cfg(trader).is_empty(), "its menu is there while the place is free")
	c.tide.steps = 40
	check(c.station_cfg(trader).is_empty(), "no trade once the tide has taken it")
	check(c.dock_block(trader) != "", "and you can't dock")


func test_a_hollow_place_is_called_the_hollow_but_a_named_one_keeps_its_name() -> void:
	var c := Campaign.new(3)
	var id := ""
	for o in c.neighbours("rusthold"):
		if c.node(o)["name"] == "" and c.node(o)["type"] != "station":
			id = o
			break
	check(id != "", "an unnamed neighbour of the start")
	var before := c.label(id)
	check(before != "The Hollow" and before != "?", "known, with its type: " + before)
	c.tide.steps = 40
	eq(c.label(id), "The Hollow", "once the tide has taken it")
	eq(c.label("rusthold"), "Gantry Rusthold", "a station holds and keeps its name")
	var far := ""
	for n in c.drift.nodes:
		if not c.is_known(n["id"]) and n["name"] == "":
			far = n["id"]
			break
	eq(c.label(far), "?", "an unknown place is still a question mark")


func test_arriving_starts_the_linger_clock_again() -> void:
	var ship := _ship()
	var c := Campaign.new(8)
	c.linger(200.0)
	check(c.tide.linger_left() < 41.0, "40 s from a rise")
	for o in c.neighbours(c.current):
		if c.node(o)["type"] != "gate":
			check(_jump(c, o, ship)["ok"], "jump")
			break
	eq(c.tide.linger_left(), c.tide.linger_s, "a new place, a full clock")


# --- saving ------------------------------------------------------------------------------------------------

func test_the_tide_survives_a_save_and_load() -> void:
	var c := Campaign.new(12)
	c.tide.steps = 7
	c.tide.linger_t = 200.0
	var text := JSON.stringify(c.to_dict())
	var d := Campaign.new(99)
	eq(d.load_dict(JSON.parse_string(text)), "", "loads")
	eq([d.tide.steps, d.tide.linger_t], [7, 200.0], "the tide is where it was")
	eq(JSON.stringify(d.to_dict()), text, "and saves the same again")
	var lines := d.linger(1.0)
	eq(lines, [], "the 60 s warning that was already told is not told again")
	lines = d.linger(30.0)
	eq(lines, ["The tide rises in 15 s"], "the 15 s one is still to come")


func test_an_old_save_gets_a_fresh_tide_at_its_jump_count() -> void:
	var c := Campaign.new(12)
	c.jumps = 6
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	d.erase("tide")
	d["version"] = 3
	var old := Campaign.new(1)
	eq(old.load_dict(d), "", "a version 3 save loads")
	eq([old.tide.steps, old.tide.linger_t], [6, 0.0], "a tide at its 6 jumps")
	d["version"] = 1
	d.erase("sectors")
	d.erase("spool")
	d.erase("fuel_part")
	eq(Campaign.new(1).load_dict(d), "", "so does version 1")


func test_a_broken_tide_is_refused_and_nothing_changes() -> void:
	var c := Campaign.new(12)
	c.tide.steps = 5
	var snapshot := JSON.stringify(c.to_dict())
	var good: Dictionary = JSON.parse_string(snapshot)
	var bad := good.duplicate(true)
	bad["tide"] = {"steps": "many"}
	var other := Campaign.new(2)
	other.tide.steps = 9
	check(other.load_dict(bad) != "", "a tide with no number of steps is refused")
	eq(other.tide.steps, 9, "and nothing changed")


# --- one tide per region ----------------------------------------------------------------------------------

## Walk the campaign's ship to the region's exit beacon (the jump does not matter here: the test sets the place).
func _at_exit(c: Campaign) -> void:
	c.current = c.drift.exit_id()
	c.visited[c.current] = true


func test_each_region_has_a_tide_of_its_own_from_its_entry_with_its_exit_holding() -> void:
	var ship := _ship()
	ship.inventory.add("fuel", 10)
	var c := Campaign.new(11)
	var exit := c.drift.exit_id()
	check(exit != "", "Clan space has an exit beacon")
	eq([c.tide.entry_id, c.tide.exit_id, c.tide.jumps_to_cross], [c.drift.start_id(), exit, 16], "stage 1: from Rusthold, the exit holds, 16 steps")
	c.tide.steps = 99
	check(not c.is_hollow(exit) and not c.is_hollow("rusthold"), "the exit and the station hold when everything else has fallen")
	eq(c.tide.jumps_until(exit), -1, "the exit never falls")
	var first := c.tide
	_at_exit(c)
	c.tide.linger_t = 100.0
	var r := c.cross(c.region_offers()[0], ship)
	check(r["ok"], "crossing: " + str(r["why"]))
	check(c.tide != first, "a new tide for the new region")
	eq([c.stage, c.tide.steps, c.tide.linger_t], [2, 0, 0.0], "stage 2 begins with the tide at the start")
	eq([c.tide.entry_id, c.tide.exit_id, c.tide.jumps_to_cross], [c.drift.start_id(), c.drift.exit_id(), 14], "from its own entry, its own exit, 14 steps")
	check(c.drift.exit_id() != "" and c.tide.axis_len > 0.0, "and its own axis")
	c.tide.steps = 99
	check(not c.is_hollow(c.drift.exit_id()), "this exit holds too")
	_at_exit(c)
	check(c.cross(c.region_offers()[0], ship)["ok"], "the next crossing")
	eq([c.stage, c.tide.jumps_to_cross], [3, 13], "stage 3: 13 steps")


func test_the_regions_tide_is_saved_and_old_saves_load_a_fresh_one() -> void:
	var ship := _ship()
	var c := Campaign.new(11)
	_at_exit(c)
	check(c.cross(c.region_offers()[0], ship)["ok"], "into stage 2")
	c.tide.steps = 6
	c.tide.linger_t = 30.0
	var text := JSON.stringify(c.to_dict())
	var d := Campaign.new(2)
	eq(d.load_dict(JSON.parse_string(text)), "", "loads")
	eq([d.stage, d.tide.steps, d.tide.linger_t, d.tide.jumps_to_cross, d.tide.exit_id], [2, 6, 30.0, 14, d.drift.exit_id()], "the region's tide as it was, with its stage's speed")
	eq(JSON.stringify(d.to_dict()), text, "and saves the same again")
	var old: Dictionary = JSON.parse_string(text)
	old.erase("tide")
	old["version"] = 4
	var e := Campaign.new(2)
	eq(e.load_dict(old), "", "a regions-era save with no tide loads")
	eq([e.stage, e.tide.steps, e.tide.jumps_to_cross], [2, 0, 14], "a fresh tide, since its jump count is not this region's")
	var first := Campaign.new(3)
	first.jumps = 5
	var older: Dictionary = JSON.parse_string(JSON.stringify(first.to_dict()))
	older.erase("tide")
	older["version"] = 4
	var f := Campaign.new(2)
	eq(f.load_dict(older), "", "so does one from stage 1")
	eq([f.tide.steps, f.tide.exit_id], [5, f.drift.exit_id()], "at its jump count, with the exit holding")


# --- a fight at a Hollow place pays almost nothing ---------------------------------------------------------

## A Hollow place of campaign `c` (steps 40) with the ship standing there, and a beaten enemy to cut up.
func _ghost_fight() -> Dictionary:
	var ship := _ship()
	var c := Campaign.new(3)
	for n in c.drift.nodes:
		if n["type"] in ["pirate", "wreck_field", "distress", "asteroid_field", "empty"]:
			c.current = n["id"]
			break
	c.tide.steps = 40
	var enemy = Ship.from_design("res://data/ships/pirate_raider.json")
	return {"c": c, "ship": ship, "enemy": enemy}


func test_a_ghost_fight_pays_no_credits_and_no_scrap_up_front() -> void:
	for state in ["won", "captured"]:
		var g := _ghost_fight()
		var c: Campaign = g["c"]
		var ship: Ship = g["ship"]
		check(c.is_hollow(c.current), "the ship is at a Hollow place")
		var credits := ship.inventory.count("credits")
		var scrap := ship.inventory.count("scrap")
		var r := c.fight_done({"state": state, "enemy": g["enemy"]}, ship)
		eq(r["lines"], [], state + ": nothing is paid at the fight")
		eq([ship.inventory.count("credits"), ship.inventory.count("scrap")], [credits, scrap], state + ": no credits, no scrap (a captured ghost pays no strip scrap either)")
		eq(c.fights_won, 1, state + ": still a win")
		check(str(r["text"]).contains("ghost"), state + ": the ghost goes dark")
	var s := _ghost_fight()
	var c2: Campaign = s["c"]
	var ship2: Ship = s["ship"]
	var credits2 := ship2.inventory.count("credits")
	var spared := c2.fight_done({"state": "spared", "enemy": s["enemy"], "offer": {"credits": 50, "fuel": 2}}, ship2)
	eq(spared["lines"], [], "a ghost's offer to be spared is refused")
	eq(ship2.inventory.count("credits"), credits2, "and not paid")
	var free := Campaign.new(3)  # the same fight at a free place still pays
	var ship3 := _ship()
	free.fight_done({"state": "won", "enemy": s["enemy"]}, ship3)
	check(ship3.inventory.count("credits") > 300, "a free place pays its credits (the Rustbucket starts with 300)")


func test_a_ghost_wreck_offers_only_the_strip_row_at_half_the_scrap() -> void:
	var g := _ghost_fight()
	var c: Campaign = g["c"]
	var ship: Ship = g["ship"]
	var enemy = g["enemy"]
	var full := Salvage.strip_scrap(enemy, c)
	eq(Salvage.strip_scrap(enemy, c, true), full / 2, "half the formula")
	for state in ["won", "captured"]:
		for flag in [null, true]:  # the flag left out reads the campaign: the ship is at a Hollow place
			var ev := Salvage.event_for(enemy, state, c, ship, flag)
			eq(ev["choices"].size(), 1, "%s, flag %s: one row, no part and no scan" % [state, str(flag)])
			var row: Dictionary = ev["choices"][0]
			eq(row["text"], "Strip her for scrap (+%d)" % (full / 2), "the half strip row")
			eq(row["outcomes"][0]["text"], "Nothing aboard is right. Your cutters take the plating and leave the rest.", "its text")
			eq(row["outcomes"][0]["effects"], {"items": {"scrap": full / 2}}, "pays the half scrap")
			eq([ev["id"], ev["type"]], ["salvage", "salvage"], "an event the panel shows as it is")
	var before := ship.inventory.count("scrap")
	var ev2 := Salvage.event_for(enemy, "won", c, ship)
	var r := c.events.choose(ev2, 0, c, ship, c.node(c.current))
	check(r["ok"], "the row can be taken")
	eq(ship.inventory.count("scrap"), before + full / 2, "and gives the half scrap")
	var normal := Salvage.event_for(enemy, "won", c, ship, false)
	check(normal["choices"].size() > 1, "with the flag off the ghost rule is off: the parts are there again")
	c.tide.steps = 0
	check(Salvage.event_for(enemy, "won", c, ship)["choices"].size() > 1, "and at a free place the full salvage is offered")


# --- the map view and the clock line -----------------------------------------------------------------------

## A map view in play mode on a sim with the Rustbucket: the map shut, build mode off, a fake combat view.
func _play() -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [_ship()]
	var fake := FakeCombat.new()
	var build := BuildMode.new()
	build.sim = sim
	build.build_on = false
	var map := MapView.new()
	map.sim = sim
	map.combat = fake
	map.build = build
	map.size = Vector2(1600.0, 900.0)
	map.new_game(5)
	map.visible = false
	return {"map": map, "sim": sim, "fake": fake, "build": build}


func _free_play(d: Dictionary) -> void:
	for k in d:
		d[k].free()


func test_the_map_view_lingers_only_in_play_mode_with_the_map_shut_and_no_fight() -> void:
	var d := _play()
	var map: MapView = d["map"]
	eq(map.tick_linger(10.0), [], "no lines yet")
	eq(map.campaign.tide.linger_t, 10.0, "play mode, map shut, no fight: it counts")
	d["build"].build_on = true
	map.tick_linger(10.0)
	eq(map.campaign.tide.linger_t, 10.0, "build mode does not count")
	d["build"].build_on = false
	d["fake"].active = true
	map.tick_linger(10.0)
	eq(map.campaign.tide.linger_t, 10.0, "a fight does not count")
	d["fake"].active = false
	map.visible = true
	map.tick_linger(10.0)
	eq(map.campaign.tide.linger_t, 10.0, "the open map does not count")
	map.visible = false
	var before: int = map.ship().events.size()
	var lines := map.tick_linger(230.0)
	eq([map.campaign.tide.steps, lines.has(Tide.RISES_TEXT)], [1, true], "and 240 s in all raise the tide")
	check(map.ship().events.size() > before and map.ship().events[-1]["text"] == Tide.RISES_TEXT, "the lines reach the chronicle")
	_free_play(d)


func test_the_tooltip_and_the_status_bar_speak_of_the_tide() -> void:
	var d := _play()
	var map: MapView = d["map"]
	var c: Campaign = map.campaign
	var id := ""
	for n in c.drift.nodes:
		if n["type"] == "pirate" or n["type"] == "wreck_field":
			id = n["id"]
			break
	var found := {}
	for s in 40:
		c.tide.steps = s
		var n := c.tide.jumps_until(id)
		if n == 2 and not found.has(2):
			eq(map.tide_tip(id), ["The tide reaches here in 2 jumps"], "two jumps off")
			found[2] = true
		elif n == 1 and not found.has(1):
			eq(map.tide_tip(id), ["The tide reaches here in 1 jump"], "one jump off")
			found[1] = true
		elif n == 0 and not found.has(0):
			eq(map.tide_tip(id), ["Hollow: ghost ships, no trade"], "taken")
			found[0] = true
	eq(found.size(), 3, "all three cases were seen")
	eq(map.tide_tip("rusthold"), ["Holds against the tide"], "a station holds")
	c.tide.steps = 0
	c.tide.linger_t = 79.0
	eq(map.tide_status(), "Tide: holds / 2:41", "at Rusthold: it holds there, and the clock has 161 s")
	c.current = id
	check(map.tide_status().begins_with("Tide: ") and map.tide_status().ends_with(" jumps / 2:41"), "elsewhere: jumps until it reaches the ship: " + map.tide_status())
	c.tide.steps = 40
	eq(map.tide_status(), "Tide: Hollow / --", "taken, and nothing left to count")
	_free_play(d)


func test_the_play_mode_line_shows_in_play_and_hides_elsewhere() -> void:
	var d := _play()
	var map: MapView = d["map"]
	var hud := TideHud.new()
	hud.map = map
	eq(hud.line(), "Hollow tide: rises in 4:00", "the whole period")
	eq(hud.tint(), TideHud.TEXT, "violet-grey while there is time")
	map.campaign.tide.linger_t = 200.0
	eq([hud.line(), hud.tint()], ["Hollow tide: rises in 0:40", TideHud.AMBER], "amber under 60 s")
	map.campaign.tide.linger_t = 230.0
	eq([hud.line(), hud.tint()], ["Hollow tide: rises in 0:10", TideHud.RED], "red under 15 s")
	d["build"].build_on = true
	eq(hud.line(), "", "hidden in build mode")
	d["build"].build_on = false
	d["fake"].active = true
	eq(hud.line(), "", "hidden in a fight")
	d["fake"].active = false
	map.visible = true
	eq(hud.line(), "", "hidden while the map is open")
	map.visible = false
	map.campaign.tide.steps = 99
	eq(hud.line(), "", "hidden once the tide has taken everything")
	map.campaign.tide.steps = 0
	var no_campaign := TideHud.new()
	eq(no_campaign.line(), "", "hidden with no map or campaign")
	var empty_map := MapView.new()
	no_campaign.map = empty_map
	eq(no_campaign.line(), "", "and with a map that has no campaign yet")
	empty_map.free()
	no_campaign.free()
	hud.free()
	_free_play(d)


func test_the_map_view_adds_the_line_to_its_own_canvas_layer() -> void:
	var layer := CanvasLayer.new()
	var map := MapView.new()
	layer.add_child(map)
	map._make_tide_hud()
	check(map.tide_hud != null and map.tide_hud.get_parent() == layer and map.tide_hud.map == map, "a sibling in the layer, wired to the map")
	map._make_tide_hud()
	eq(layer.get_child_count(), 2, "only once")
	layer.free()


# --- the content -------------------------------------------------------------------------------------------

func test_the_pack_has_six_hollow_events_with_fights_and_a_free_way_out() -> void:
	var ev: Events = Events.shared()
	var hollow: Array = ev.order.filter(func(id): return str(ev.events[id].get("type", "")) == "hollow" and Content.origin("events", id) == "mech_tide")  # the story_1 pack adds its own clue-bearing tide events
	check(hollow.size() >= 6, "six hollow events (%d)" % hollow.size())
	eq(hollow.filter(func(id): return Content.origin("events", id) == "mech_tide").size(), 6, "six of them from the tide pack (events_2 adds six more)")
	var fights := 0
	for id in hollow:
		var e: Dictionary = ev.events[id]
		check(["mech_tide", "events_2"].has(Content.origin("events", id)), id + ": from the tide pack or the events refresh")
		var free := false
		var fight := false
		for ch in e["choices"]:
			var plain: bool = not ch.has("requires") and not ch.has("pay")
			var costs := false
			for o in ch["outcomes"]:
				var eff: Dictionary = o.get("effects", {})
				if not eff.is_empty():
					costs = true
				if eff.get("fight", "") == "tier":
					fight = true
			if plain and not costs:
				free = true
		check(free, id + ": a choice that is free in every outcome")
		fights += int(fight)
	check(fights >= 3, "at least 3 lead to a fight (%d)" % fights)
	var errs := ev.validate()
	check(errs.is_empty(), "the validator is happy with every event: " + "; ".join(errs))
	var c := Campaign.new(1)
	c.tide.steps = 40
	for i in 30:
		var picked: Dictionary = ev.pick(c, {"id": "n01", "type": "hollow", "place": ""}, _ship())
		eq(picked.get("type", ""), "hollow", "a pick is a hollow event")


## A jump along a lane the way the game makes one now (docs/CONTENT.md section 11): spool the drive and let it fire.
## The jump() result ({ok, why, node, drift, notes}).
func _jump(c: Campaign, to: String, ship, drift := false) -> Dictionary:
	var r: Dictionary = c.start_jump(to, ship, false, drift)
	if not r["ok"]:
		return {"ok": false, "why": r["why"], "notes": []}
	c.tick_jump(c.spool_time(), false, ship)
	return c.last_jump
