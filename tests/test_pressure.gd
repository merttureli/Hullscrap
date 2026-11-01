extends "res://tests/base_test.gd"
## The Hollow tide pushes you (docs/waves/playtest_2.md S4): the pressure of a place (tide.gd pressure: 0 two or more steps from falling,
## 0.3 rising to 1 over the last step, 1 when Hollow), the campaign handing it to the sector (set_pressure), the debris thinning by
## lerp(1, 0.4, pressure), the fog that creeps in from the left (hollow_fog.gd), the tide clock pulsing red under 30 s and the
## "The Hollow is near. Jump soon." toast with the 60 s warning of the place that falls next.

const Campaign = preload("res://scripts/space/campaign.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Tide = preload("res://scripts/space/tide.gd")
const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Content = preload("res://scripts/data/content.gd")
const HollowFog = preload("res://scripts/view/hollow_fog.gd")
const DebrisView = preload("res://scripts/view/debris_view.gd")
const TideHud = preload("res://scripts/ui/tide_hud.gd")
const TideTest = preload("res://tests/test_tide.gd")
const SectorViewTest = preload("res://tests/test_sector_view.gd")


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## The id of a place of `c`'s map the tide can still take, with the tide set to one step short of taking it.
func _edge_node(c: Campaign) -> String:
	var best := ""
	var best_k := 1000
	for n in c.drift.nodes:
		var id := str(n["id"])
		var k := c.tide.jumps_until(id)
		if k >= 1 and k < best_k and str(n["type"]) != "gate":
			best = id
			best_k = k
	check(best != "", "this map has a place the tide can still take")
	c.tide.steps += best_k - 1
	eq(c.tide.jumps_until(best), 1, "one step short of taking it")
	return best


func _go(c: Campaign, id: String) -> void:
	c.current = id
	c.visited[id] = true
	c.current_sector().enter()


func test_pressure_is_0_far_off_rises_from_a_third_over_the_last_step_and_is_1_when_hollow() -> void:
	var h = TideTest.new()
	var t: Tide = h._line_tide()  # grace 2, 100 px a step: "c" (250 px) falls at step 5
	eq(t.jumps_until("c"), 5, "c falls in 5 steps")
	near(t.pressure("c"), 0.0, "5 steps off: none")
	t.steps = 3
	eq(t.jumps_until("c"), 2, "2 steps off")
	near(t.pressure("c"), 0.0, "2 steps from falling: still none")
	t.steps = 4
	eq(t.jumps_until("c"), 1, "1 step off")
	near(t.pressure("c"), 0.3, "the last step begins at 0.3")
	t.linger_t = 120.0
	near(t.pressure("c"), 0.65, "half way through the linger clock: 0.65")
	t.linger_t = 239.9
	near(t.pressure("c"), 1.0, "and 1 as the clock runs out", 0.01)
	var last := 0.0
	for k in 25:
		t.linger_t = 240.0 * float(k) / 25.0
		check(t.pressure("c") >= last, "the pressure only rises through the step")
		last = t.pressure("c")
	t.linger_t = 0.0
	t.advance(1)
	near(t.pressure("c"), 1.0, "Hollow: 1")
	near(t.pressure("a"), 0.0, "a station never feels it")
	near(t.pressure("d"), 0.0, "nor a place that holds")
	near(t.pressure("nope"), 0.0, "nor a place the map does not have")
	t.steps = 99
	near(t.pressure("a"), 0.0, "even when the whole map has fallen")
	var quick: Tide = Tide.make(h._line_map(), "a", {"grace": 2, "jumps_to_cross": 10, "linger_s": 240, "pressure_from": 0.5}, "", 1)
	quick.steps = 4
	near(quick.pressure("c"), 0.5, "the starting pressure is data/tide.json pressure_from")
	near(Tide.config()["pressure_from"], 0.3, "0.3 in the shipped data")


func test_the_campaign_gives_the_sector_its_pressure_and_a_gate_never_feels_it() -> void:
	var c := Campaign.new(8)
	var id := _edge_node(c)
	_go(c, id)
	c._mark_hollow()
	var s = c.current_sector()
	near(s.pressure, 0.3, "arriving a step short of the fall: 0.3")
	c.tide.linger_t = 100.0
	c.linger(20.0)
	near(s.pressure, 0.3 + 0.7 * 120.0 / 240.0, "lingering raises it (120 s of 240)")
	near(c.tide_pressure(id), s.pressure, "the campaign's number is the sector's")
	check(not s.hollow, "and the place is not Hollow yet")
	c.linger(c.tide.linger_s)
	check(s.hollow and c.is_hollow(id), "the tide takes it")
	near(s.pressure, 1.0, "Hollow: 1")
	c.tide.steps -= 3
	c._mark_hollow()
	near(s.pressure, 0.0, "the tide pushed back two steps off: nothing")
	var other := ""
	for n in c.drift.nodes:
		if str(n["id"]) != id and str(n["type"]) not in ["station", "gate", "exit"]:
			other = str(n["id"])
			break
	c.sectors.erase(other)
	c.tide.steps += c.tide.jumps_until(other) - 1
	c.tide.linger_t = 0.0
	near(c.sector_at(other).pressure, c.tide_pressure(other), "a sector made later is told when it is made")
	near(c.tide_pressure(other), 0.3, "a step short of the fall")
	for n in c.drift.nodes:
		if str(n["type"]) == "gate":
			c.tide.steps = 99
			near(c.tide_pressure(str(n["id"])), 0.0, "a Dead Gate, which the tide never takes, never feels it")
			c.tide.steps = 0
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	check(not JSON.stringify(d["sectors"]).contains("pressure"), "the pressure is not saved")
	var c2 := Campaign.new(1)
	c2.tide.steps = 0
	eq(c2.load_dict(d), "", "loads")
	near(c2.current_sector().pressure, c2.tide_pressure(c2.current), "a load sets it again from the tide")


func test_the_debris_density_is_multiplied_by_lerp_1_to_0_4_before_the_hollow_multiplier() -> void:
	var base: Dictionary = Content.read(DriftDebris.PATH)
	var s = Sector.generate(3, {"id": "t1", "name": "", "type": "wreck_field", "place": ""}, "boneyard")
	var rate0 := 1.0 / float(s.debris_cfg(base)["spawn"]["every"])
	var cap0 := float(s.debris_cfg(base)["spawn"]["max_alive"])
	for row in [[0.0, 1.0], [0.3, 0.82], [0.5, 0.7], [1.0, 0.4]]:
		s.set_pressure(row[0])
		var cfg: Dictionary = s.debris_cfg(base)
		near(1.0 / float(cfg["spawn"]["every"]) / rate0, row[1], "pressure %.1f: the spawn rate is x%.2f" % [row[0], row[1]], 1e-6)
		near(float(cfg["spawn"]["max_alive"]) / cap0, row[1], "and the cap", 0.03)
	s.set_pressure(1.0)
	s.set_hollow(true)
	near(1.0 / float(s.debris_cfg(base)["spawn"]["every"]) / rate0, 0.4 * 0.3, "Hollow at pressure 1: the 0.4 first, then the Hollow place's 0.3", 1e-6)
	s.set_pressure(5.0)
	near(s.pressure, 1.0, "the pressure is kept in 0 to 1")
	s.set_pressure(-1.0)
	near(s.pressure, 0.0, "from 0")


func test_the_60_second_warning_of_the_place_that_falls_next_adds_the_toast_line() -> void:
	var c := Campaign.new(8)
	var id := _edge_node(c)
	_go(c, id)
	c.tide.linger_t = 175.0  # 65 s left
	var lines := c.linger(6.0)
	check(lines.has("The tide rises in 60 s"), "the 60 s warning")
	check(lines.has(Tide.NEAR_TEXT), "and this place falls next: " + str(lines))
	eq(Tide.NEAR_TEXT, "The Hollow is near. Jump soon.", "the words")
	c.tide.linger_t = 220.0
	lines = c.linger(6.0)
	check(lines.has("The tide rises in 15 s") and not lines.has(Tide.NEAR_TEXT), "the 15 s warning says only that")
	var far := Campaign.new(8)
	var id2 := _edge_node(far)
	far.tide.steps -= 1
	_go(far, id2)
	far.tide.linger_t = 175.0
	lines = far.linger(6.0)
	check(lines.has("The tide rises in 60 s") and not lines.has(Tide.NEAR_TEXT), "two steps off: the warning, not the toast")


func test_the_fog_grows_from_the_left_as_the_pressure_does() -> void:
	near(HollowFog.band_width(0.0, 1600.0), 0.0, "no pressure, no fog")
	var third := HollowFog.band_width(1.0, 1600.0) / 1600.0
	check(third >= 0.3 and third <= 0.37, "at 1 the band covers about a third of the screen (%.2f)" % third)
	var w := -1.0
	var a := -1.0
	for k in 11:
		var p := float(k) / 10.0
		check(HollowFog.band_width(p, 1600.0) > w and HollowFog.band_alpha(p) > a, "wider and denser at %.1f" % p)
		w = HollowFog.band_width(p, 1600.0)
		a = HollowFog.band_alpha(p)
	near(HollowFog.band_width(2.0, 1600.0), HollowFog.band_width(1.0, 1600.0), "and capped at pressure 1")
	var fog := HollowFog.new()
	fog.size = Vector2(1600.0, 900.0)
	fog._process(0.1)
	check(not fog.visible, "nothing is shown at 0")
	fog.pressure = 0.6
	fog._process(0.1)
	check(fog.visible, "and the fog at 0.6")
	fog.free()


func test_the_sector_view_carries_the_pressure_to_the_fog_and_the_debris() -> void:
	var h = SectorViewTest.new()
	var d: Dictionary = h._screen(8)
	var view = d["view"]
	var c: Campaign = d["map"].campaign
	var ship = d["sim"].player_ship()
	var id := _edge_node(c)
	c.current = id
	c.visited[id] = true
	c._enter(id, ship)
	view.frame(0.05)
	near(view._fog.pressure, 0.3, "the fog knows the sector's pressure")
	var dv := DebrisView.new()
	dv.sim = d["sim"]
	dv.build = d["build"]
	dv.sector = view
	dv.frame(0.1)
	var field = dv.debris
	var every := float(dv.debris.cfg["spawn"]["every"])
	c.tide.linger_t = 100.0
	c.linger(0.01)
	view.frame(0.05)
	dv.frame(0.1)
	var p: float = c.current_sector().pressure
	near(p, 0.3 + 0.7 * 100.0 / 240.0, "the clock moved the pressure", 0.001)
	near(view._fog.pressure, p, "the fog follows")
	check(dv.debris == field, "the same field: rescaled, not rebuilt")
	near(float(dv.debris.cfg["spawn"]["every"]) / every, lerpf(1.0, 0.4, 0.3) / lerpf(1.0, 0.4, p), "the debris thins as the tide nears", 1e-3)
	var spawn: Dictionary = dv.debris.cfg["spawn"].duplicate()
	dv.frame(0.1)
	eq(dv.debris.cfg["spawn"], spawn, "and takes the numbers once")
	dv.free()
	h._free(d)


func test_the_tide_clock_is_red_and_pulses_under_30_seconds() -> void:
	var h = TideTest.new()
	var d: Dictionary = h._play()
	var map = d["map"]
	var hud := TideHud.new()
	hud.map = map
	var tide: Tide = map.campaign.tide
	tide.linger_t = 200.0  # 40 s left
	eq(hud.tint(), TideHud.AMBER, "amber at 40 s")
	near(hud.pulse(0.1), 0.0, "and still")
	tide.linger_t = 215.0  # 25 s left
	eq(hud.tint(), TideHud.RED, "red under 30 s")
	near(hud.pulse(0.0), 0.5, "the pulse sits half way at t 0")
	near(hud.pulse(1.0 / 6.0), 1.0, "peaks a quarter period on (1.5 pulses a second)", 1e-3)
	near(hud.pulse(0.5), 0.0, "and dims")
	tide.linger_t = 235.0  # 5 s left
	eq(hud.tint(), TideHud.RED, "red to the end")
	check(hud.pulse(0.25) != hud.pulse(0.5), "pulsing")
	hud.free()
	h._free_play(d)
