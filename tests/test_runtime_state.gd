extends "res://tests/base_test.gd"
## The runtime state of placed components (hp, heat, status): saving, power, the chronicle, the F key (an order to the crew) and the HUD.

const Fixture = preload("res://tests/fixture_ship.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Components = preload("res://scripts/ship/components.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")


## Reactor (x 10..13), consumer (x 15..18; a fabricator: a hull mount would need a wall to come back from a save) and oxygen generator (x 15..16, y 12..15) on one cable.
func _ship() -> Dictionary:
	var ship := Fixture.room_ship()
	var d := {"ship": ship}
	d["reactor"] = Fixture.put(ship, "reactor_mk1", 10, 10)
	d["part"] = Fixture.put(ship, "fabricator", 15, 10)
	d["gen"] = Fixture.put(ship, "oxygen_gen", 15, 12)
	Fixture.wire(ship, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11), Vector2i(15, 12)])
	ship.refresh()
	return d


func test_new_instances_start_healthy() -> void:
	var d := _ship()
	var inst: Dictionary = d["ship"].components.instances[d["reactor"]]
	eq([inst["hp"], inst["heat"], inst["status"]], [8, 0.0, "ok"], "reactor hp, heat, status")
	eq(d["ship"].components.instances[d["part"]]["hp"], 4, "part hp")


func test_parts_that_are_not_ok_are_not_powered() -> void:
	var d := _ship()
	var ship: Ship = d["ship"]
	check(ship.power_state["powered"][d["part"]] and ship.power_state["powered"][d["gen"]], "all powered at first")
	for status in ["overheated", "malfunction", "disabled"]:
		ship.components.instances[d["part"]]["status"] = status
		ship.refresh()
		check(not ship.power_state["powered"][d["part"]], status + " part is not powered")
		check(ship.power_state["powered"][d["gen"]], "the rest still runs")
		ship.components.instances[d["part"]]["status"] = "ok"
		ship.refresh()
		check(ship.power_state["powered"][d["part"]], "ok again: powered")
	ship.components.instances[d["reactor"]]["status"] = "malfunction"
	ship.refresh()
	check(not ship.power_state["powered"][d["reactor"]], "a malfunctioning reactor makes no power")
	check(not ship.power_state["powered"][d["gen"]] and not ship.power_state["powered"][d["part"]], "and so nothing else runs")
	eq(ship.power_state["networks"][0]["supply"], 0, "no supply")


func test_state_round_trips_through_save_and_load() -> void:
	var d := _ship()
	var a: Ship = d["ship"]
	var inst: Dictionary = a.components.instances[d["part"]]
	inst["hp"] = 2
	inst["heat"] = 37.5
	inst["status"] = "malfunction"
	a.components.instances[d["reactor"]]["status"] = "overheated"
	a.components.instances[d["reactor"]]["heat"] = 100.0
	var saved: Dictionary = JSON.parse_string(JSON.stringify(a.to_dict()))
	var b := Ship.new_starter()
	eq(b.load_dict(saved), "", "loads")
	var got: Dictionary = b.components.instances[d["part"]]
	eq([got["hp"], got["heat"], got["status"]], [2, 37.5, "malfunction"], "part state")
	eq([b.components.instances[d["reactor"]]["status"], b.components.instances[d["reactor"]]["heat"]], ["overheated", 100.0], "reactor state")
	eq(b.components.instances[d["gen"]]["status"], "ok", "a healthy part stays healthy")
	check(not b.power_state["powered"][d["part"]] and not b.power_state["powered"][d["reactor"]], "power is solved with the loaded statuses")
	eq(JSON.stringify(b.to_dict()), JSON.stringify(a.to_dict()), "and it saves back the same")


func test_version_1_parts_load_as_new() -> void:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	var old := {"version": 1, "next_uid": 3, "instances": [{"uid": 2, "id": "reactor_neon_mk1", "anchor": [4, 4], "rot": 0}]}
	eq(c.load_dict(old), "", "a version 1 save loads")
	var inst: Dictionary = c.instances[2]
	eq([inst["hp"], inst["heat"], inst["status"]], [8, 0.0, "ok"], "full hp, cold, ok")
	eq(c.to_dict()["version"], 3, "and saves as version 3")
	eq(c.load_dict({"version": 4, "next_uid": 1, "instances": []}), "unsupported components version", "newer is refused")
	var odd := {"version": 2, "next_uid": 3, "instances": [{"uid": 2, "id": "engine_mk1", "anchor": [4, 4], "rot": 0, "hp": 99, "heat": -5, "status": "exploded"}]}
	eq(c.load_dict(odd), "", "odd state loads")
	inst = c.instances[2]
	eq([inst["hp"], inst["heat"], inst["status"]], [6, 0.0, "ok"], "clamped and defaulted")


func test_a_ship_save_with_version_1_parts_still_loads() -> void:
	var d := _ship()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(d["ship"].to_dict()))
	saved["components"]["version"] = 1
	for i in saved["components"]["instances"]:
		i.erase("hp")
		i.erase("heat")
		i.erase("status")
	var b := Ship.new_starter()
	eq(b.load_dict(saved), "", "loads")
	eq(b.components.instances[d["part"]]["status"], "ok", "as new")


func test_the_chronicle_keeps_the_last_50() -> void:
	var ship := Fixture.room_ship()
	ship.clock = 12.0
	for i in 60:
		ship.log_event("event %d" % i)
	eq(ship.events.size(), 50, "capped at 50")
	eq(ship.events[0], {"t": 12.0, "text": "event 10"}, "oldest dropped, {t, text}")
	eq(ship.events[-1]["text"], "event 59", "newest last")


func _mode(ship: Ship) -> BuildMode:
	var sim := ShipSim.new()
	sim.ships = [ship]
	var b := BuildMode.new()
	b.sim = sim
	return b


func _done(b: BuildMode) -> void:
	b.sim.free()
	b.free()


func test_f_sends_the_nearest_crew_member_to_repair_the_part_under_the_mouse() -> void:
	var d := _ship()
	var ship: Ship = d["ship"]
	var inst: Dictionary = ship.components.instances[d["part"]]
	inst["status"] = "malfunction"
	inst["hp"] = 3
	var b := _mode(ship)
	b.hover = Vector2i(16, 10)  # inside the engine
	var e := InputEventKey.new()
	e.keycode = KEY_F
	e.pressed = true
	b._on_key(e)
	eq(b.message, "no crew to send", "nobody aboard to go")
	var near := CrewMember.new("Near", Vector2(16.0, 13.0))
	var far := CrewMember.new("Far", Vector2(20.0, 15.0))
	ship.crew.append_array([far, near])
	b._on_key(e)
	eq(b.message, "Near will repair Fabricator", "the nearest one goes")
	eq(near.job.get("type"), "repair_component", "and has the job")
	check(far.job.is_empty(), "the other stays")
	for i in 100:  # build mode pauses the world: the order waits
		b.sim.step(0.1)
	eq([inst["status"], inst["hp"]], ["malfunction", 3], "nothing is repaired while the world is paused")
	b.build_on = false
	for i in 100:  # 5 s of work after the walk
		b.sim.step(0.1)
	eq([inst["status"], inst["hp"]], ["ok", 4], "repaired in play mode")
	b.build_on = true
	b._on_key(e)
	eq(b.message, "Fabricator needs no repair", "nothing to do the second time")
	b.hover = Vector2i(20, 14)
	b._on_key(e)
	eq(b.message, "no system under the mouse", "empty floor")
	b.build_on = false
	inst["status"] = "malfunction"
	b.hover = Vector2i(16, 10)
	b._on_key(e)
	eq(b.message, "no system under the mouse", "F only works in build mode: the message is left alone")
	eq(inst["status"], "malfunction", "F only works in build mode")
	_done(b)


func test_the_hud_log_shows_the_last_three_events() -> void:
	var ship := Fixture.room_ship()
	ship.clock = 75.0
	var b := _mode(ship)
	var hud := Hud.new()
	hud.setup(b)
	var text := func() -> String: return "\n".join(hud.log_panel.lines().map(func(l): return l[0]))
	check(not text.call().contains("malfunctioned"), "no events, no lines")
	ship.log_event("Kickjet malfunctioned")
	ship.log_event("Prism Core overheated")
	ship.log_event("Third")
	ship.log_event("Fourth")
	var log_text: String = text.call()
	check(not log_text.contains("Kickjet malfunctioned"), "only the last three")
	check(log_text.contains("[1:15] Prism Core overheated") and log_text.contains("[1:15] Fourth"), "with the time")
	hud.free()
	_done(b)


func test_the_hud_shows_fractional_power() -> void:
	var d := _ship()
	d["ship"].components.remove_at(Vector2i(10, 10))
	Fixture.put(d["ship"], "reactor_scrap_mk1", 10, 10)
	d["ship"].refresh()
	var b := _mode(d["ship"])
	var hud := Hud.new()
	hud.setup(b)
	var power: Dictionary = hud.top_bar.items().filter(func(it): return it["id"] == "power")[0]
	eq(power["text"], "5.4 / 4", "the top bar shows 5.4 supply against 4 demand")
	hud.free()
	_done(b)
