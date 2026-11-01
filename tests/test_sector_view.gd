extends "res://tests/base_test.gd"
## Sector space step 2 (docs/CONTENT.md section 11, the view): the helm (helm.gd: the autopilot to a course, round big
## rocks, the player's hand, cruise x1.8, who mans it, the frame that puts the ship's cells in the sector), the sector
## view (sector_view.gd: play mode flies in the sector and the build screen holds, markers set a course, POIs trigger into
## the panels, the map spools the jump and the ship arrives, E at the helm, fights in place and the wrecks they leave,
## saves resume where the ship was), the debris round a flying ship (drift_debris.gd frame) and the sector's new save
## fields.

const Helm = preload("res://scripts/space/helm.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Radar = preload("res://scripts/space/radar.gd")
const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const SectorView = preload("res://scripts/view/sector_view.gd")
const DebrisView = preload("res://scripts/view/debris_view.gd")
const Content = preload("res://scripts/data/content.gd")
const Wall = preload("res://tests/fixture_wall.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const SAVE := "user://test_sector_view_campaign.json"


## Stands in for the crew view: the player's soldier.
class FakeCrew extends Node2D:
	var player


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.refresh()
	return s


func _sector(type := "empty"):
	return Sector.generate(1, {"id": "t0", "name": "", "type": type, "place": ""}, "clans")


## A helm on `ship` in `s`, at `at`, heading up and still.
func _helm(ship, s, at: Vector2) -> Helm:
	var h := Helm.new()
	h.refresh(ship)
	h.place(at)
	return h


## Fly until the course is done or `cap` seconds pass, `dt` a step. Returns the seconds flown.
func _fly(h: Helm, s, cap := 200.0, dt := 0.1, rocks: Array = [], watch: Callable = Callable()) -> float:
	var t := 0.0
	while not h.course.is_empty() and t < cap:
		h.step(dt, s, true, {}, false, rocks)
		t += dt
		if watch.is_valid():
			watch.call()
	return t


# --- the helm --------------------------------------------------------------------------------------------------

func test_the_autopilot_flies_to_a_course_and_stops_within_300_px() -> void:
	var ship := _ship()
	var s = _sector()
	var h := _helm(ship, s, Vector2(4000.0, 4000.0))
	eq(h.why_not, "", "the Rustbucket can fly")
	var to := Vector2(10000.0, 8500.0)
	h.set_course_to(to)
	var t := _fly(h, s)
	check(h.course.is_empty(), "the course is done")
	eq(h.arrived, "the marked point", "and the helm says it arrived")
	check(h.flight.pos.distance_to(to) <= 300.0, "within 300 px: %d" % h.flight.pos.distance_to(to))
	check(h.flight.vel.length() <= 60.0, "and nearly still: %d px/s" % h.flight.vel.length())
	check(t < 60.0, "an 7,500 px trip at cruise takes well under a minute: %.1f s" % t)
	eq(s.ship_pos, h.flight.pos, "the sector knows where the ship is")
	near(s.ship_angle, h.flight.angle, "and its heading")


func test_the_autopilot_arrives_from_any_heading_and_drift() -> void:
	var ship := _ship()
	var s = _sector()
	for k in 6:
		var h := _helm(ship, s, Vector2(12000.0, 12000.0))
		h.place(Vector2(12000.0, 12000.0), Vector2.from_angle(k * 1.1) * 900.0, k * 1.3 - 3.0)
		var to := Vector2(12000.0, 12000.0) + Vector2.from_angle(k * 2.3) * (3000.0 + 1000.0 * k)
		h.set_course_to(to)
		_fly(h, s, 240.0, 0.25)
		check(h.course.is_empty() and h.flight.pos.distance_to(to) <= 300.0, "case %d: arrived (%d px off, state %s)" % [k, h.flight.pos.distance_to(to), h.state])


func test_the_autopilot_steers_round_a_big_rock_in_its_path() -> void:
	var ship := _ship()
	var s = _sector()
	var from := Vector2(4000.0, 6000.0)
	var to := Vector2(12000.0, 6000.0)
	var rock := {"pos": Vector2(7000.0, 6000.0), "r": 30.0}
	var closest := [INF]
	var h := _helm(ship, s, from)
	h.flight.angle = PI / 2.0
	h.set_course_to(to)
	_fly(h, s, 200.0, 0.1, [rock], func(): closest[0] = minf(closest[0], h.flight.pos.distance_to(rock["pos"])))
	check(h.course.is_empty(), "it still arrives")
	check(closest[0] > h.radius + float(rock["r"]), "it kept clear of the rock: %d px from its centre (hull radius %d)" % [closest[0], h.radius])
	var blind := [INF]
	var g := _helm(ship, s, from)
	g.flight.angle = PI / 2.0
	g.set_course_to(to)
	_fly(g, s, 200.0, 0.1, [], func(): blind[0] = minf(blind[0], g.flight.pos.distance_to(rock["pos"])))
	check(blind[0] < float(rock["r"]) + 40.0, "with no rock to see it flies straight through that spot (%d px)" % blind[0])


func test_cruise_is_x1_8_out_of_combat_and_real_near_a_hostile() -> void:
	var ship := _ship()
	var s = _sector()
	var h := _helm(ship, s, Vector2(5000.0, 5000.0))
	var base := Vector2(h.flight.thrust_to_accel, h.flight.max_speed)
	h.step(0.1, s, true)
	eq(float(h.cfg["cruise"]), 1.8, "data/sectors.json: cruise 1.8 (it was 3: the owner found open space too fast)")
	near(h.cruise, 1.8, "cruise x1.8 with nothing hostile near")
	near(h.flight.thrust_to_accel, base.x * 1.8, "acceleration x1.8")
	near(h.flight.max_speed, base.y * 1.8, "top speed x1.8")
	h.step(0.1, s, true, {}, true)
	near(h.cruise, 1.0, "a hostile within 2,500 px: real numbers")
	near(h.flight.max_speed, base.y, "real top speed")
	eq(int(h.cfg["real_within"]), 2500, "data/sectors.json: real numbers within 2,500 px")


func test_unmanned_it_coasts_and_a_ship_that_cannot_fly_stays_put() -> void:
	var ship := _ship()
	var s = _sector()
	var h := _helm(ship, s, Vector2(5000.0, 5000.0))
	h.flight.vel = Vector2(200.0, 0.0)
	h.set_course_to(Vector2(9000.0, 5000.0))
	h.step(1.0, s, false)
	eq(h.state, "unmanned", "nobody at the helm")
	near(h.flight.vel.length(), 200.0 * exp(-h.flight.linear_damping), "it only coasts, slowing with the damping", 0.5)
	check(not h.course.is_empty(), "the course waits for someone")
	for uid in ship.components.instances.keys():
		if str(ship.components.def(ship.components.instances[uid]["id"]).get("family", "")) == "engine":
			ship.components.remove_uid(uid)
	ship.mark_dirty()
	h.refresh(ship)
	eq(h.why_not, "no powered engine", "no engines left")
	h.manual = true
	h.place(Vector2(5000.0, 5000.0))
	h.step(1.0, s, true, {"throttle": 1.0})
	eq(h.state, "grounded", "the helm says the ship cannot fly")
	check(not h.manual, "and the player's hand lets go")
	eq(h.flight.pos, Vector2(5000.0, 5000.0), "it stays where it was")


func test_the_players_hand_flies_with_the_combat_controls() -> void:
	var ship := _ship()
	var s = _sector()
	var h := _helm(ship, s, Vector2(5000.0, 5000.0))
	h.manual = true
	for i in 10:
		h.step(0.1, s, false, {"throttle": 1.0, "side": 0.0, "cursor": null})
	eq(h.state, "manual", "the player flies, manned or not")
	check(h.flight.vel.y < -10.0 and absf(h.flight.vel.x) < 1.0, "W thrusts along the heading (up): %s" % str(h.flight.vel))
	var g := _helm(ship, s, Vector2(5000.0, 5000.0))
	g.manual = true
	for i in 20:
		g.step(0.1, s, false, {"throttle": 0.0, "side": 0.0, "cursor": Vector2(6000.0, 5000.0)})
	check(g.flight.angle > 0.3, "the mouse to the right turns the ship clockwise toward it: %.2f" % g.flight.angle)


func test_the_frame_puts_the_ships_cells_where_the_arena_would() -> void:
	var ship := _ship()
	var s = _sector()
	var h := _helm(ship, s, Vector2(7000.0, 3000.0))
	h.flight.angle = 0.9
	var arena := Arena.new(1)
	arena.add_ship(ship, h.flight.pos, h.flight.angle)
	eq(h.pivot, arena.ships[0].pivot, "the same pivot as the arena")
	var f := h.frame(ship)
	var origin: Vector2 = ship.world_pos - Vector2(ship.grid.size) * 32.0 / 2.0
	for c in [Vector2i(0, 0), Vector2i(3, 7), Vector2(ship.grid.size) - Vector2(1, 1)]:
		var cell := Vector2(c)
		var want: Vector2 = arena.local_to_world(0, cell + Vector2(0.5, 0.5))
		var got: Vector2 = f * (origin + (cell + Vector2(0.5, 0.5)) * 32.0)
		check(got.distance_to(want) < 0.01, "cell %s: %s, the arena has %s" % [str(c), str(got), str(want)])


func test_the_helm_is_manned_by_crew_at_it_or_the_player_beside_it() -> void:
	var ship := _ship()
	ship.manned.clear()
	var helms := Helm.helms(ship)
	check(helms.size() >= 1, "the Rustbucket has a helm")
	var player = ship.crew.filter(func(m): return m.is_player)[0]
	var spots: Array = Jobs.new().stand_spots(ship, {"type": "man_station", "cells": ship.components.instances[helms[0]]["cells"]})
	player.pos = Vector2(-50.0, -50.0)
	check(not Helm.is_manned(ship, player), "nobody at the helm")
	ship.manned[helms[0]] = "Juno"
	check(Helm.is_manned(ship, player), "a crew member at it")
	ship.manned.clear()
	player.pos = Pathfinder.centre_of(spots[0])
	eq(Helm.helm_near(ship, player), helms[0], "the player beside it")
	check(Helm.is_manned(ship, player), "counts too")
	ship.components.instances[helms[0]]["status"] = "disabled"
	check(not Helm.is_manned(ship, player), "a broken helm flies nothing")


# --- the sector view -----------------------------------------------------------------------------------------------

## The play screen without a window: the ship sim, BuildMode in play mode, the map (which owns a campaign of `seed_value`
## on the light-speed flow), the combat view, the crew's player and the sector view, wired as main.tscn does.
func _screen(seed_value := 5) -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [_ship()]
	var build := BuildMode.new()
	build.sim = sim
	var map := MapView.new()
	map.sim = sim
	map.build = build
	map.size = Vector2(1600.0, 900.0)
	build.drift = map
	var combat := CombatView.new()
	combat.sim = sim
	combat.build = build
	map.combat = combat
	combat.finished.connect(map._on_fight_finished)
	var crew := FakeCrew.new()
	crew.player = sim.player_ship().crew.filter(func(m): return m.is_player)[0]
	var view := SectorView.new()
	view.sim = sim
	view.build = build
	view.combat = combat
	view.crew = crew
	view.cam = Camera2D.new()
	combat.sector = view
	combat.finished.connect(view._on_fight_finished)
	build.hostiles_source = view.red_alert_hostiles
	map.new_game(seed_value)
	map.visible = false  # as _ready leaves it
	map.save_path = SAVE
	build.build_on = false
	view.frame(0.05)
	return {"sim": sim, "build": build, "map": map, "combat": combat, "crew": crew, "view": view}


func _free(d: Dictionary) -> void:
	if d["combat"].active:
		d["combat"].leave()
	d["view"].cam.free()
	for k in ["view", "crew", "combat", "map", "build", "sim"]:
		d[k].free()


func test_play_mode_flies_in_the_sector_and_the_build_screen_holds() -> void:
	var d := _screen()
	var view = d["view"]
	var build = d["build"]
	var c: Campaign = d["map"].campaign
	var s = c.current_sector()
	check(view.flying(), "the light-speed flow: the ship is in sector space")
	eq(view.helm.flight.pos, s.arrival, "at the sector's arrival point")
	eq(view.cam.position, s.arrival, "the camera on the ship")
	check(build.transform.is_equal_approx(view.helm.frame(d["sim"].player_ship())), "the interior is drawn where the ship flies")
	view.manned_override = true
	view.choose(str(s.main_poi()["id"]))
	for i in 20:
		view.frame(0.1)
	check(view.helm.flight.vel.length() > 20.0, "with a course and the helm manned it flies")
	build.build_on = true
	view.frame(0.1)
	var held: Vector2 = s.ship_pos
	for i in 20:
		view.frame(0.1)
	eq(s.ship_pos, held, "the build screen holds the world")
	eq(build.transform, Transform2D.IDENTITY, "and shows the ship upright at the origin")
	eq(view.cam.position, Vector2.ZERO, "with the camera there")
	check(not view.visible, "and nothing of the sector")
	_free(d)


func test_a_marker_sets_the_course_and_again_cancels_it() -> void:
	var d := _screen()
	var view = d["view"]
	var s = d["map"].campaign.current_sector()
	var id := str(s.main_poi()["id"])
	check(view.choose(id), "a known POI")
	eq(view.helm.course, {"poi": id}, "the course follows it")
	check(view.helm_line().begins_with("AUTOPILOT") or view.helm_line().begins_with("HELM UNMANNED") or view.helm_line().begins_with("No course"), "the helm line says what it does")
	view._markers = [{"rect": Rect2(100.0, 100.0, 40.0, 40.0), "id": id}]
	view.visible = true
	check(view.click(Vector2(120.0, 120.0)), "a click on its marker")
	eq(view.helm.course, {}, "on the course's own marker it cancels")
	check(not view.click(Vector2(500.0, 500.0)), "a click elsewhere is not the view's")
	check(not view.choose("nowhere"), "an unknown POI")
	_free(d)


func test_flying_to_rusthold_brings_ma_gantry_then_the_station_menu() -> void:
	var d := _screen()
	var view = d["view"]
	var map: MapView = d["map"]
	var s = map.campaign.current_sector()
	view.manned_override = true
	view.choose(str(s.main_poi()["id"]))
	var t := 0.0
	while not map.visible and t < 120.0:
		view.frame(0.25)
		t += 0.25
	check(map.visible and map.panel_only, "the POI's event opens over the sector after %.1f s" % t)
	check(s.ship_pos.distance_to(s.main_poi()["pos"]) <= float(s.cfg["poi"]["trigger"]) + 1.0, "within 800 px of the station")
	eq(map.event_panel.event.get("id", ""), "station_debt_intro", "Ma Gantry's introduction")
	var pos: Vector2 = s.ship_pos
	view.frame(1.0)
	eq(s.ship_pos, pos, "the sector holds while the event is up")
	map.event_panel.choose(0)
	map.event_panel.proceed()
	check(map.station_panel.visible and map.station_panel.station == "rusthold", "then Rusthold's menu")
	map.station_panel.close()
	check(not map.visible, "then the sector again")
	view.frame(0.25)
	check(not map.visible, "and the station does not greet again while the ship is there")
	_free(d)


func test_the_map_spools_the_jump_and_the_ship_arrives_in_the_next_sector() -> void:
	var d := _screen()
	var view = d["view"]
	var map: MapView = d["map"]
	var c: Campaign = map.campaign
	var ship = d["sim"].player_ship()
	var to := ""
	for o in c.neighbours(c.current):
		if c.node(o)["type"] != "gate":
			to = o
	map.open()
	eq(map.click_node(to), "", "a linked node")
	check(not map.visible and c.jump_status()["active"], "the map closes and the drive spools")
	view.frame(0.1)
	check(view.spool_line().begins_with("JUMP DRIVE:"), "the HUD shows the spool: " + view.spool_line())
	var t := 0.0
	while c.current != to and t < 10.0:
		view.frame(0.25)
		t += 0.25
	eq(c.current, to, "it fired")
	near(t, 8.0, "after 8 s", 0.6)
	eq(ship.inventory.count("fuel"), 5, "one fuel spent")
	eq(view.helm.flight.pos, c.current_sector().arrival, "the ship is at the new sector's arrival point")
	check(view.message.begins_with("Arrived at"), "and the HUD says so: " + view.message)
	eq(view.spool_line(), "", "the drive is idle")
	_free(d)


func test_e_at_the_helm_takes_it_and_e_again_hands_it_back() -> void:
	var d := _screen()
	var view = d["view"]
	var ship = d["sim"].player_ship()
	var player = d["crew"].player
	player.pos = Vector2(-50.0, -50.0)
	check(not view.toggle_helm(), "away from the helm E is the door key")
	var helm_uid: int = Helm.helms(ship)[0]
	player.pos = Pathfinder.centre_of(Jobs.new().stand_spots(ship, {"type": "man_station", "cells": ship.components.instances[helm_uid]["cells"]})[0])
	check(view.toggle_helm(), "at the helm E takes it")
	check(view.helm.manual and view.piloting(), "the player flies: WASD stop walking the soldier")
	view.hand_override = {"throttle": 1.0, "side": 0.0, "cursor": null}
	for i in 10:
		view.frame(0.1)
	eq(view.helm.state, "manual", "by hand")
	check(view.helm.flight.vel.length() > 10.0, "W thrusts")
	check(view.toggle_helm(), "E again")
	check(not view.helm.manual and not view.piloting(), "hands it back")
	_free(d)


func test_a_fight_in_the_sector_starts_where_the_ship_flies_and_a_win_leaves_a_wreck() -> void:
	var d := _screen()
	var view = d["view"]
	var combat = d["combat"]
	var c: Campaign = d["map"].campaign
	var s = c.current_sector()
	view.helm.place(Vector2(9000.0, 9000.0), Vector2(100.0, 0.0), 0.5)
	eq(combat.enter(Session.PIRATE_PATH), "", "K: the test pirate")
	check(combat.in_sector, "a fight in the sector")
	var mine = combat.session.arena.ships[Session.PLAYER]
	var foe = combat.session.arena.ships[Session.ENEMY]
	eq(mine.flight.pos, Vector2(9000.0, 9000.0), "the ship fights where it flew")
	near(mine.flight.angle, 0.5, "heading as it was")
	near(foe.flight.pos.distance_to(mine.flight.pos), Session.SPAWN_DISTANCE, "the pirate appears 1,200 px off", 0.5)
	view.frame(0.1)
	eq(s.hostiles, [foe.flight.pos], "the sector knows the hostile")
	var to: String = c.neighbours(c.current).filter(func(o): return c.node(o)["type"] != "gate")[0]
	eq(c.start_jump(to, d["sim"].player_ship(), s.hostile_near(c.hostile_range()))["why"], Campaign.HOSTILES_TEXT, "no jump with it within 2,000 px")
	check(view.ship_frame().is_equal_approx(Helm.frame_of(d["sim"].player_ship(), mine.flight.pos, mine.flight.angle, mine.pivot)), "the debris follows the ship in the fight")
	combat.session.arena.wreck(Session.ENEMY)
	var wreck_at: Vector2 = foe.flight.pos
	for i in 8:
		if combat.active:
			combat.frame(0.5)
	check(not combat.active, "a wreck: the fight ends by itself after a while")
	eq(s.wrecks.size(), 1, "the wreck stays as a POI")
	if s.wrecks.size() == 1:
		check(s.wrecks[0]["pos"].distance_to(wreck_at) < 50.0, "where the pirate died")
		eq(s.wrecks[0]["state"], Sector.DONE, "marked salvaged (the map's salvage pick is the only one)")
		check(Radar.contacts(s, d["sim"].player_ship()).any(func(ct): return ct["poi"]["id"] == s.wrecks[0]["id"]), "on the radar")
	eq(view.helm.flight.pos, mine.flight.pos, "the ship is where the fight left it")
	check(s.hostiles.is_empty(), "no hostile left")
	eq(combat.enter(Session.PIRATE_PATH), "", "another")
	var far = combat.session.arena.ships[Session.ENEMY]
	far.flight.pos = combat.session.arena.ships[Session.PLAYER].flight.pos + Vector2(Session.LEAVE_DISTANCE + 500.0, 0.0)
	combat.frame(0.05)
	check(not combat.active, "out of range: over at once")
	eq(s.wrecks.size(), 1, "and nothing was wrecked")
	_free(d)


func test_an_event_fight_spawns_at_its_poi_and_resolves_it_after() -> void:
	var d := _screen()
	var view = d["view"]
	var map: MapView = d["map"]
	var combat = d["combat"]
	var c: Campaign = map.campaign
	var s = c.current_sector()
	var poi: Dictionary = s.main_poi()
	view.helm.place(poi["pos"] + Vector2(700.0, 0.0))
	view.frame(0.01)
	var ev := {"id": "test_ambush", "type": "pirate", "text": "Guns.", "choices": [{"text": "Fight.", "outcomes": [{"weight": 100, "text": "", "effects": {"fight": "pirate_raider"}}]}]}
	map.open_poi({"poi": poi, "refused": "", "event": ev, "dock": false}, s)
	map.event_panel.choose(0)
	check(combat.active and combat.in_sector, "the fight starts in the sector")
	var foe = combat.session.arena.ships[Session.ENEMY]
	var mine = combat.session.arena.ships[Session.PLAYER]
	check(foe.flight.pos.distance_to(poi["pos"]) <= 600.0 + 1.0 or absf(foe.flight.pos.distance_to(mine.flight.pos) - Session.SPAWN_DISTANCE) < 1.0,
		"the enemy appears at the POI (or kept 1,200 px off the ship): %d px from it" % foe.flight.pos.distance_to(poi["pos"]))
	check(not map.visible, "the panels step aside")
	combat.session.arena.wreck(Session.ENEMY)
	for i in 8:
		if combat.active:
			combat.frame(0.5)
	check(map.visible and map.event_panel.visible, "the loot notice")
	map.event_panel.proceed()
	check(map.event_panel.visible and map.event_panel.event.get("id", "") == "salvage", "then the salvage pick of the pirate's parts, as from any fight")
	map.event_panel.choose(map.event_panel.view.size() - 1)
	map.event_panel.proceed()
	check(not map.visible, "then the sector")
	check(s.main_poi()["state"] == Sector.DONE or bool(s.cfg["poi_types"][s.main_poi()["type"]].get("repeat", false)), "the POI is resolved")
	eq(s.wrecks.size(), 1, "the wreck stays where it died")
	check(s.wrecks.all(func(w): return w["state"] == Sector.DONE), "already salvaged: no second pick from it")
	_free(d)


func test_a_save_resumes_in_the_sector_where_the_ship_was() -> void:
	var d := _screen()
	var view = d["view"]
	var map: MapView = d["map"]
	var s = map.campaign.current_sector()
	view.manned_override = true
	view.helm.set_course_to(s.arrival + Vector2(2500.0, 0.0).rotated(1.0))
	for i in 30:
		view.frame(0.2)
	s.add_wreck(Vector2(3333.0, 4444.0), "Wreck of a test")
	var pos: Vector2 = view.helm.flight.pos
	var angle: float = view.helm.flight.angle
	check(pos.distance_to(s.arrival) > 100.0, "the ship has flown off")
	eq(map.save_campaign(), "", "saved")
	map.new_game(99)
	view.frame(0.05)
	check(view.helm.flight.pos.distance_to(pos) > 1.0, "a new run is elsewhere")
	eq(map.load_campaign(), "", "loaded")
	view.frame(0.0)
	check(view.helm.flight.pos.distance_to(pos) < 0.5, "back where it was: %s, saved %s" % [str(view.helm.flight.pos), str(pos)])
	near(view.helm.flight.angle, angle, "heading as it was", 1e-4)
	var w: Array = map.campaign.current_sector().wrecks
	check(w.size() == 1 and w[0]["name"] == "Wreck of a test" and w[0]["pos"] == Vector2(3333.0, 4444.0), "with its wreck")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	_free(d)


func test_an_older_sector_save_with_no_heading_or_wrecks_still_loads() -> void:
	var s = _sector()
	var old: Dictionary = s.to_save()
	old.erase("angle")
	old.erase("wrecks")
	old.erase("next_wreck")
	var t = _sector()
	eq(t.load_save(old), "", "loads")
	check(t.wrecks.is_empty(), "no wrecks")
	var bad: Dictionary = s.to_save()
	bad["wrecks"] = [{"id": 3}]
	eq(t.load_save(bad), "bad sector data", "a malformed wreck is refused")
	var w = s.add_wreck(Vector2(100.0, 200.0))
	eq(w["id"], "w1", "wrecks are numbered")
	eq(s.add_wreck(Vector2.ZERO)["id"], "w2", "in turn")
	check(s.all_pois().has(w) and s.find("w1") == w, "a wreck is a POI like the others")
	s.resolve("w1")
	eq(w["state"], Sector.DONE, "salvaged once")
	for p in s.pois:
		p["state"] = Sector.DONE
	check(s.cleared(), "a wreck left to salvage does not keep a sector from being cleared")


# --- debris round a flying ship ------------------------------------------------------------------------------

## The wall fixture with a Net Mouth through it, outside half facing up: {ship, mouth (build px)}.
func _net() -> Dictionary:
	var ship := Wall.wall_ship(1, 0)
	var depth: int = ship.components.by_id["net_mouth_scrap"]["mount"]["outside"][1]
	ship.components.place_mount(ship.grid, "net_mouth_scrap", Wall.out_anchor(0, depth), 0)
	ship.refresh()
	return {"ship": ship, "mouth": DriftDebris.new(1).intakes(ship)[0]["rect"]}


func test_a_turned_flying_ship_catches_debris_at_its_mouth_and_bounces_the_rest() -> void:
	var rig := _net()
	var ship: Ship = rig["ship"]
	var d := DriftDebris.new(3)
	d.frame = Transform2D(PI / 2.0, Vector2(9000.0, 7000.0))
	d.frame_vel = Vector2(150.0, 0.0)
	d.view_centre = d.frame * ship.world_pos
	var scrap := ship.inventory.count("scrap")
	var p: Dictionary = d.add_piece("scrap_chunk_s", d.frame * rig["mouth"].get_center(), Vector2.ZERO)
	d.step(ship, 0.05)
	check(not d.pieces.has(p), "a piece at the turned mouth, in sector px, is caught")
	eq(ship.inventory.count("scrap") - scrap, 2, "into the hold")
	var e: Array = d.take_events()
	check(e.size() == 1 and e[0]["pos"].distance_to(d.frame * rig["mouth"].get_center()) < 1.0, "the pop is at the mouth, in sector px")
	var wall := Wall.at(0, -5, 0)
	var origin: Vector2 = ship.world_pos - Vector2(ship.grid.size) * 32.0 / 2.0
	var inside: Vector2 = origin + (Vector2(wall) + Vector2(0.5, 0.1)) * 32.0
	var q: Dictionary = d.add_piece("scrap_chunk_s", d.frame * inside, Vector2.ZERO)
	d.step(ship, 0.05)
	check(d.pieces.has(q), "a piece on plain hull is not collected")
	var local: Vector2 = d.frame.affine_inverse() * q["pos"]
	check(local.y < origin.y + Vector2(wall).y * 32.0 + 1.0, "it is pushed out of the wall, outward in the ship's frame: %s" % str(local))
	check(q["vel"].dot(d.frame.basis_xform(Vector2.UP)) > 0.0 or q["vel"].x > 100.0, "knocked away by the hull")


func test_debris_spawns_ahead_of_a_ship_that_outruns_the_current() -> void:
	var rig := _net()
	var ship: Ship = rig["ship"]
	var cfg: Dictionary = Content.read(DriftDebris.PATH).duplicate(true)
	cfg["current"]["angle"] = 90  # south
	cfg["current"]["wobble_deg"] = 0
	var still := DriftDebris.new(1, cfg)
	var p: Dictionary = still._spawn(ship)
	check(p["pos"].y < 0.0, "a still ship: pieces come from upstream, the north")
	var fast := DriftDebris.new(1, cfg)
	fast.frame_vel = Vector2(0.0, 900.0)
	check(fast.flow_dir().y < 0.0, "flying south faster than the current, the debris streams north past the ship")
	var q: Dictionary = fast._spawn(ship)
	check(q["pos"].y > 0.0, "so it appears ahead, to the south")
	check(q["vel"].y > 0.0, "while it still moves with the current, south")


func test_debris_keeps_drifting_through_a_fight_in_the_sector() -> void:
	var d := _screen()
	var dv := DebrisView.new()
	dv.sim = d["sim"]
	dv.build = d["build"]
	dv.sector = d["view"]
	dv.frame(0.1)
	check(dv.debris != null, "debris in the sector")
	near(float(dv.debris.cfg["current"]["angle"]), d["map"].campaign.current_sector().current_angle, "on the sector's current")
	eq(d["combat"].enter(Session.PIRATE_PATH), "", "a fight")
	d["view"].frame(0.05)
	var t: float = dv.debris.time
	dv.frame(0.2)
	check(dv.debris.time > t, "the debris drifts on through it")
	check(dv.debris.frame.is_equal_approx(d["view"].ship_frame()), "round the fighting ship")
	dv.free()
	_free(d)


# --- morale, red alert, play time ------------------------------------------------------------------------------

func test_a_decided_fight_in_the_sector_keeps_the_six_states_and_ends_by_itself() -> void:
	var d := _screen()
	var combat = d["combat"]
	var s = d["map"].campaign.current_sector()
	var got := []
	combat.finished.connect(func(r): got.append(r))
	eq(combat.enter(Session.PIRATE_PATH), "", "a fight in the sector")
	combat.session.morale.state = "offering"
	combat.session.morale.offer = {"credits": 30}
	eq(combat.session.accept_surrender(), "", "Y: the surrender is taken")
	eq(combat.session.state(), "spared", "spared")
	for i in 8:
		if combat.active:
			combat.frame(0.5)
	check(not combat.active, "a deal: the fight ends by itself")
	check(got.size() == 1 and got[0]["state"] == "spared" and got[0].get("offer", {}).has("credits") and got[0]["in_sector"], "the result keeps its state and offer: %s" % str(got))
	check(s.wrecks.is_empty(), "a spared ship leaves no wreck")
	got.clear()
	eq(combat.enter(Session.PIRATE_PATH), "", "another")
	combat.session.morale.state = "captured"  # its crew all down (morale.gd)
	eq(combat.session.state(), "captured", "captured")
	for i in 8:
		if combat.active:
			combat.frame(0.5)
	check(got.size() == 1 and got[0]["state"] == "captured", "the fight ends captured")
	eq(s.wrecks.size(), 1, "the captured hulk stays as a POI")
	_free(d)


func test_red_alert_in_sector_space_refuses_the_build_screen() -> void:
	var d := _screen()
	var view = d["view"]
	var build = d["build"]
	var s = d["map"].campaign.current_sector()
	eq(build.can_build(), "", "nothing hostile about: build mode is open")
	s.ambient.append({"id": "a9", "type": "unknown", "name": "Unknown ship", "pos": s.ship_pos + Vector2(1800.0, 0.0), "visibility": "signal",
		"event_type": "pirate", "state": Sector.NEW, "enemy": "", "main": false, "ambient": true, "vel": Vector2.ZERO, "ttl": 100.0})
	check(build.can_build() != "", "a pirate 1,800 px off: red alert")
	build.set_build(true)
	check(not build.build_on, "B is refused")
	s.ambient[-1]["pos"] = s.ship_pos + Vector2(2600.0, 0.0)
	eq(build.can_build(), "", "past 2,500 px it is clear")
	s.ambient[-1]["pos"] = s.ship_pos + Vector2(100.0, 0.0)
	s.ambient[-1]["event_type"] = "trader"
	eq(build.can_build(), "", "a trader is no hostile")
	s.ambient.clear()
	view.helm.place(Vector2(9000.0, 9000.0))
	eq(d["combat"].enter(Session.PIRATE_PATH), "", "a fight")
	view.frame(0.05)
	check(view.red_alert_hostiles().size() == 1 and view.red_alert_hostiles()[0].distance_to(d["sim"].player_ship().world_pos) < Session.SPAWN_DISTANCE + 50.0, "its enemy is on the list, in the build screen's frame")
	_free(d)


func test_in_play_and_the_played_signal_count_only_play_time() -> void:
	var d := _screen()
	var view = d["view"]
	var t := [0.0]
	view.played.connect(func(dt): t[0] += dt)
	view.frame(0.5)
	check(view.in_play(), "play mode in the sector: in play")
	near(t[0], 0.5, "played: 0.5 s")
	d["map"].open()
	view.frame(0.5)
	check(not view.in_play(), "the map open: not")
	d["map"].close()
	d["build"].build_on = true
	view.frame(0.5)
	check(not view.in_play(), "build mode: not")
	d["build"].build_on = false
	d["combat"].enter(Session.PIRATE_PATH)
	view.frame(0.5)
	check(not view.in_play(), "a fight: not")
	near(t[0], 0.5, "only the play time was counted")
	_free(d)
