extends "res://tests/base_test.gd"
## Lines (data/lines.json) and the effective stats of a component (scripts/sim/stats.gd).

const Fixture = preload("res://tests/fixture_ship.gd")
const Stats = preload("res://scripts/sim/stats.gd")
const Components = preload("res://scripts/ship/components.gd")
const Flight = preload("res://scripts/sim/flight.gd")
const Power = preload("res://scripts/sim/power.gd")


func _comps() -> Components:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	return c


func _near(got: float, want: float, msg: String) -> void:
	check(absf(got - want) < 0.0001, "%s: expected %s, got %s" % [msg, want, got])


func test_lines_table() -> void:
	var lines := Stats.load_lines()
	eq(lines.keys().size(), 3, "three lines")
	var want := {
		"scrap": [0.5, 1.2, 0.9, 1.2, 1.1, 0.5, 0.15, 1.0],
		"standard": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.01, 1.0],
		"neon": [2.0, 0.9, 1.3, 0.7, 1.5, 1.5, 0.03, 2.0],
	}
	for id in want:
		var l: Dictionary = lines[id]
		var got := [l["cost"], l["power"], l["output"], l["mass"], l["heat"], l["repair"], l["malfunction_per_min"], l["ion_vulnerability"]]
		eq(got, want[id], id + " line")
	eq(Stats.load_lines("res://data/nothing.json"), {}, "a missing file gives no lines")


func test_every_component_has_runtime_fields_and_a_known_line() -> void:
	var c := _comps()
	var lines := Stats.load_lines()
	for id in c.ids():
		var d := c.def(id)
		check(lines.has(d["line"]), id + " has a known line")
		check(d["hp"] > 0 and d["heat_limit"] == 100, id + " hp and heat limit")
		check(d["cooling"] >= 3, id + " cools")
	eq([c.def("reactor_mk1")["hp"], c.def("engine_mk1")["hp"], c.def("shield_mk1")["hp"], c.def("laser_mk1")["hp"], c.def("oxygen_gen")["hp"], c.def("helm")["hp"]], [8, 6, 6, 5, 5, 4], "hp by family")
	eq([c.def("reactor_mk1")["heat_per_s"], c.def("engine_mk1")["heat_per_s"], c.def("laser_mk1")["heat_per_s"], c.def("shield_mk1")["heat_per_s"], c.def("helm")["heat_per_s"]], [4.0, 3.0, 2.0, 2.0, 0.0], "heat per second by family")
	eq([c.def("reactor_mk1")["cooling"], c.def("engine_mk1")["cooling"]], [5.0, 3.0], "cooling")
	eq(c.def("reactor_neon_mk1")["heat_per_s"], 10, "the Prism Core runs hot")
	eq(c.def("radiator")["stats"]["cooling_bonus"], 6, "radiator bonus")
	eq(c.def("radiator")["size"], [2, 2], "radiator is 2x2")
	for id in ["reactor_scrap_mk1", "engine_scrap_mk1", "oxygen_scrap_mk1", "reactor_neon_mk1", "engine_neon_mk1", "radiator"]:
		check(c.def(id).get("blurb", "") != "", id + " has a blurb")
		eq(c.def(id)["size"], c.def({"reactor_scrap_mk1": "reactor_mk1", "engine_scrap_mk1": "engine_mk1", "oxygen_scrap_mk1": "oxygen_gen", "reactor_neon_mk1": "reactor_mk1", "engine_neon_mk1": "engine_mk1", "radiator": "radiator"}[id])["size"], id + " size")
	eq([c.def("reactor_scrap_mk1")["name"], c.def("engine_scrap_mk1")["name"], c.def("oxygen_scrap_mk1")["name"], c.def("reactor_neon_mk1")["name"], c.def("engine_neon_mk1")["name"]],
		["Rustbucket Reactor", "Kickjet", "Wheezer O2", "Prism Core", "Ion Drive: Glimmer"], "names")


func test_scrap_and_neon_multiply_the_output() -> void:
	var c := _comps()
	var lines := Stats.load_lines()
	var scrap := Stats.effective(c.def("reactor_scrap_mk1"), lines)
	_near(scrap["power"], float(c.def("reactor_scrap_mk1")["power"]) * 0.9, "scrap reactor gives its power x 0.9")
	_near(Stats.effective(c.def("reactor_neon_mk1"), lines)["power"], float(c.def("reactor_neon_mk1")["power"]) * 1.3, "neon reactor gives its power x 1.3")
	_near(Stats.effective(c.def("engine_neon_mk1"), lines)["stats"]["thrust"], 10 * 1.3, "neon engine thrust x 1.3")
	_near(Stats.effective(c.def("engine_scrap_mk1"), lines)["stats"]["thrust"], 10 * 0.9, "scrap engine thrust x 0.9")
	_near(Stats.effective(c.def("oxygen_scrap_mk1"), lines)["stats"]["o2_rate"], 0.6 * 0.9, "scrap O2 rate x 0.9")
	var std := Stats.effective(c.def("engine_mk1"), lines)
	eq(std["stats"]["thrust"], 10.0, "a standard engine is unchanged")
	eq(std["power"], -2, "and so is its draw (a whole number stays an int)")


func test_power_draw_heat_mass_and_reliability_follow_the_line() -> void:
	var c := _comps()
	var lines := Stats.load_lines()
	_near(Stats.effective(c.def("engine_scrap_mk1"), lines)["power"], -2 * 1.2, "scrap draws x 1.2")
	_near(Stats.effective(c.def("engine_neon_mk1"), lines)["power"], -2 * 0.9, "neon draws x 0.9")
	var n := Stats.effective(c.def("reactor_neon_mk1"), lines)
	_near(n["heat_per_s"], 10 * 1.5, "neon heat x 1.5")
	_near(n["mass_mult"], 0.7, "neon mass")
	_near(n["malfunction_per_min"], 0.03, "neon malfunctions 3% a minute")
	_near(n["repair_mult"], 1.5, "neon repairs slower")
	_near(n["ion_vulnerability"], 2.0, "neon is ion-weak")
	_near(n["cost_mult"], 2.0, "neon costs double")
	eq([n["hp"], n["heat_limit"], n["cooling"]], [8, 100.0, 5.0], "hp, limit and cooling are the part's own")
	var s := Stats.effective(c.def("engine_scrap_mk1"), lines)
	_near(s["heat_per_s"], 3 * 1.1, "scrap heat x 1.1")
	_near(s["mass_mult"], 1.2, "scrap mass")
	_near(s["malfunction_per_min"], 0.15, "scrap malfunctions 15% a minute")
	_near(s["repair_mult"], 0.5, "scrap repairs fast")
	_near(Stats.effective(c.def("reactor_mk1"), lines)["malfunction_per_min"], 0.01, "standard 1%")


func test_effective_stats_are_a_copy_and_unknown_lines_are_standard() -> void:
	var c := _comps()
	var lines := Stats.load_lines()
	var e := Stats.effective(c.def("engine_neon_mk1"), lines)
	e["stats"]["thrust"] = 1.0
	eq(c.def("engine_neon_mk1")["stats"]["thrust"], 10, "the def is untouched")
	var odd := c.def("engine_mk1").duplicate(true)
	odd["line"] = "mystery"
	eq(Stats.effective(odd, lines)["stats"]["thrust"], 10.0, "unknown line: no change")
	eq(Stats.effective(odd, {})["malfunction_per_min"], 0.0, "and no malfunctions")
	eq(Stats.effective({"id": "x", "power": -1}, lines)["hp"], 4, "default hp")


func test_mass_mults_only_list_lines_that_change_mass() -> void:
	var m := Stats.mass_mults(_comps(), Stats.load_lines())
	_near(m["engine_scrap_mk1"], 1.2, "scrap")
	_near(m["reactor_neon_mk1"], 0.7, "neon")
	check(not m.has("engine_mk1"), "standard is left out")


func test_power_uses_the_line_numbers() -> void:
	var ship := Fixture.room_ship()
	var r := Fixture.put(ship, "reactor_scrap_mk1", 10, 10)  # 2x4, x 10..11, y 10..13
	var o := Fixture.put(ship, "oxygen_scrap_mk1", 15, 10)  # 2x4, x 15..16
	var e := Fixture.put(ship, "engine_scrap_mk1", 10, 14)  # 2x2, x 10..11, y 14..15
	var l := Fixture.put(ship, "laser_mk1", 15, 14)  # 2x2, x 15..16, y 14..15
	Fixture.wire(ship, [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11), Vector2i(11, 12), Vector2i(11, 13), Vector2i(11, 14), Vector2i(15, 12), Vector2i(15, 13), Vector2i(15, 14)])
	ship.refresh()
	var n: Dictionary = ship.power_state["networks"][0]
	_near(n["supply"], float(ship.components.def("reactor_scrap_mk1")["power"]) * 0.9, "a scrap reactor supplies its power x 0.9")
	_near(n["demand"], 2.4 + 2.4 + 2.0, "scrap parts draw x 1.2")
	var p: Dictionary = ship.power_state["powered"]
	check(p[r] and p[o] and p[e], "the oxygen generator (priority 1) and the engine (4) fit in 6.3")
	check(not p[l], "the laser (5) does not: 6.3 - 4.8 = 1.5 left, it needs 2")
	_near(n["used"], 4.8, "used")


func test_flight_uses_the_line_numbers() -> void:
	var ship := Fixture.room_ship()
	var a := Fixture.put(ship, "engine_neon_mk1", 10, 10)
	var b := Fixture.put(ship, "engine_scrap_mk1", 10, 12)
	var f := Flight.new("")
	var view := Stats.view(ship.components, ship.lines)
	var powered := {a: true, b: true}
	_near(f.thrust_of(view, powered), 10 * 1.3 + 10 * 0.9, "thrust through the view")
	_near(f.thrust_of(ship.components, powered), 10.0 + 10.0, "the raw components keep the base numbers")
	var plain := f.mass_of(ship.grid, ship.components, ship.cables)
	var adjusted := f.mass_of(ship.grid, ship.components, ship.cables, Stats.mass_mults(ship.components, ship.lines))
	# two bare 2x2 engines at 3 per cell (a Flight with no data lists nothing): neon x 0.7 and scrap x 1.2
	_near(adjusted - plain, 12.0 * (0.7 - 1.0) + 12.0 * (1.2 - 1.0), "mass follows the line")
