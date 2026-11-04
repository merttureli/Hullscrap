extends "res://tests/base_test.gd"
## The playable fight without a screen: the session (spawn, groups and slots, end of the fight,
## camera framing) and the combat view node entering and leaving combat inside the real scene.

const BuildMode = preload("res://scripts/build/build_mode.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Schematic = preload("res://scripts/ui/schematic.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const PIRATE := "res://data/ships/pirate_raider.json"


func _session() -> Session:
	var s := Session.new()
	s.start(Session.load_ship(PIRATE), Session.load_ship(PIRATE), 3)
	return s


func _kinds(w: Weapons) -> Dictionary:
	var out := {}
	for id in w.defs:
		out[id] = w.group_of(id)
	return out


func test_the_enemy_spawns_1800_px_ahead_facing_the_player() -> void:
	var s := _session()
	var a = s.arena.ships[Session.PLAYER]
	var b = s.arena.ships[Session.ENEMY]
	eq(a.flight.pos, Vector2.ZERO, "the player at the origin")
	eq(b.flight.pos, Vector2(0.0, -1800.0), "the enemy straight ahead")
	near(absf(b.flight.angle), PI, "turned to face the player")
	near(s.distance(), 1800.0, "1800 px apart")
	eq(s.state(), "fighting", "on")
	eq(s.end_text(), "", "no message yet")
	s.input = {"throttle": 1.0, "turn": 0.0}
	_run(s, 1.0)
	check(a.flight.pos.y < 0.0, "the helm input flies the player")
	eq(s.arena.tick, 60, "a second of substeps")


func _run(s: Session, seconds: float) -> void:
	for i in int(seconds * 60.0):
		s.tick(1.0 / 60.0)


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func test_fire_groups_follow_the_weapon_kinds() -> void:
	var w := Weapons.new()
	var groups := _kinds(w)
	eq([groups["laser_mk1"], groups["test_bolt"], groups["test_flak"], groups["test_missile"]], [1, 1, 2, 2], "lasers and bolts 1; flak and missiles 2")
	w.defs["beamer"] = {"kind": "beam"}
	w.defs["odd"] = {"kind": "bolt", "group": 2}
	eq([w.group_of("beamer"), w.group_of("odd")], [1, 2], "a beam is group 1 and an entry's own group wins")
	var s := _session()
	var arena = s.arena
	arena.add_mount(Session.PLAYER, "test_bolt", Vector2(31.0, 28.0))
	arena.add_mount(Session.PLAYER, "test_missile", Vector2(31.0, 28.0))
	var list := s.weapons()
	eq(list.map(func(x): return x["id"]), ["laser_mk1", "rattle_burst_scrap", "test_bolt", "test_missile"], "placed weapons first, then the added ones")
	var aim: Vector2 = arena.ships[Session.ENEMY].flight.pos
	eq(s.fire_group(2, aim), 1, "the right button: the one missile")
	eq(arena.projectiles.size(), 1, "launched")
	eq(s.fire_group(1, aim), 3, "the left button: the laser, the rattle turret and the bolt, not the missile")
	eq(s.fire_group(1, aim), 0, "all cooling down")
	arena.ships[Session.PLAYER].cooldowns.clear()
	check(s.fire_slot(3, aim), "slot 3 is the bolt")
	check(not s.fire_slot(3, aim), "and it cools")
	check(not s.fire_slot(9, aim) and not s.fire_slot(0, aim), "no such slot")


func test_the_weapon_bar_states() -> void:
	var s := _session()
	var arena = s.arena
	var uid: int = s.weapons()[0]["uid"]
	var ahead: Vector2 = arena.ships[Session.ENEMY].flight.pos
	var st := s.slot_state(uid, Vector2(0.0, -1500.0))
	eq([st["status"], st["in_arc"], st["cooldown_left"], st["turret"], st["hit"]], ["ready", true, 0.0, false, -1.0], "a fixed gun: ready, and the point is inside its gimbal cone")
	st = s.slot_state(uid, Vector2(0.0, 1500.0))
	eq([st["status"], st["in_arc"]], ["ready", false], "aimed behind the ship it is still ready (it fires along its barrel), but the point is out of its cone")
	s.fire_slot(1, ahead)
	st = s.slot_state(uid, ahead)
	eq(st["status"], "cooling down", "just fired")
	check(st["cooldown_left"] > 1.0 and st["cooldown"] == 2.1, "with the cooldown counting: %s" % str(st))
	eq(s.slot_state(uid, Vector2(0.0, 1500.0))["in_arc"], false, "the cone is still out of reach while it cools")
	arena.ships[Session.PLAYER].ship.components.instances[uid]["status"] = "malfunction"
	eq(s.slot_state(uid, ahead)["status"], "malfunction", "a jammed gun")
	arena.ships[Session.PLAYER].ship.components.instances[uid]["status"] = "ok"
	arena.ships[Session.PLAYER].ship.components.instances[uid]["hp"] = 0
	arena.ships[Session.PLAYER].ship.components.instances[uid]["status"] = "disabled"
	eq(s.slot_state(uid, ahead)["status"], "disabled", "a disabled one")
	var turret: int = s.weapons()[1]["uid"]
	st = s.slot_state(turret, ahead)
	eq([st["status"], st["turret"], st["in_arc"]], ["ready", true, true], "the Rattle Burst turret: ready, the enemy is inside its arc")
	near(st["hit"], 0.6, "its hit chance against a ship that stands still: its accuracy")
	arena.ships[Session.ENEMY].flight.vel = Vector2(0.0, -arena.ships[Session.ENEMY].flight.max_speed / 2.0)
	near(s.slot_state(turret, ahead)["hit"], 0.6 - 0.125, "less the target's evasion at half its top speed")
	eq(s.slot_state(turret, Vector2(0.0, 1500.0))["status"], "ready", "a turret shoots at the enemy whatever the cursor says")
	arena.ships[Session.ENEMY].flight.pos = Vector2(0.0, 1200.0)
	eq(s.slot_state(turret, ahead)["status"], "out of arc", "but not at an enemy behind it, outside its 240 degree arc")
	eq(Schematic.component_state({"id": "x", "power": -2, "hp": 4}, {"hp": 4, "status": "ok"}, false), "unpowered", "schematic: a consumer without power")
	eq(Schematic.component_state({"id": "x", "power": -2, "hp": 4}, {"hp": 2, "status": "ok"}, true), "damaged", "schematic: damaged")
	eq(Schematic.component_state({"id": "x", "power": 4, "hp": 4}, {"hp": 4, "status": "overheated"}, true), "overheated", "schematic: overheated")


func test_the_fight_ends_when_a_ship_is_wrecked() -> void:
	var s := _session()
	check(not s.can_leave(), "cannot leave at 1800 px")
	s.arena.wreck(Session.ENEMY)
	eq(s.state(), "won", "the pirate is wrecked")
	eq(s.end_text(), "Pirate wrecked. Esc to return", "the message")
	check(s.can_leave(), "Esc works now")
	var drift: Vector2 = s.arena.ships[Session.ENEMY].flight.vel
	s.arena.ships[Session.ENEMY].flight.vel = Vector2(50.0, 0.0)
	var x: float = s.arena.ships[Session.ENEMY].flight.pos.x
	_run(s, 1.0)
	check(s.arena.ships[Session.ENEMY].flight.pos.x > x + 30.0, "the wreck keeps drifting")
	eq(drift, Vector2.ZERO, "(it was at rest)")
	s.arena.wreck(Session.PLAYER)
	eq(s.state(), "lost", "and now the player")
	eq(s.end_text(), "Your ship is wrecked. R to restart", "the message")
	var far := _session()
	far.arena.ships[Session.ENEMY].flight.pos = Vector2(0.0, -4200.0)
	check(far.can_leave(), "more than 4000 px away you may leave")
	far.arena.ships[Session.ENEMY].flight.pos = Vector2(0.0, -3900.0)
	check(not far.can_leave(), "3900 is not enough")


func test_the_jump_drive_spools_then_lets_the_player_leave() -> void:
	var s := _session()
	check(not s.can_leave(), "cannot leave at 1800 px")
	eq(s.start_jump(), "", "J starts the spool")
	eq(s.start_jump(), "The jump drive is already spooling", "once")
	var steps := int(Session.JUMP_SPOOL / Session.STEP)
	for i in steps / 2:
		s.tick(Session.STEP)
	check(not s.jump_ready() and not s.can_leave(), "not ready halfway")
	for i in steps / 2 + 10:
		s.tick(Session.STEP)
	check(s.jump_ready() and s.can_leave(), "ready after the spool: the player can leave at any range")


func test_the_camera_frames_both_ships() -> void:
	var s := _session()
	var view := Vector2(1600.0, 900.0)
	var f := s.framing(view)
	eq(f["center"], Vector2(0.0, -600.0), "the midpoint")
	var z: float = f["zoom"]
	for ship in [Session.PLAYER, Session.ENEMY]:
		var p: Vector2 = (s.arena.ships[ship].flight.pos - f["center"]) * z
		check(absf(p.x) < view.x / 2.0 and absf(p.y) < view.y / 2.0 * 0.8, "ship %d is on screen at %s" % [ship, str(p)])
	s.arena.ships[Session.ENEMY].flight.pos = Vector2(0.0, -3000.0)
	check(s.framing(view)["zoom"] < z, "it zooms out as they part")
	s.arena.ships[Session.ENEMY].flight.pos = Vector2(0.0, -100.0)
	check(s.framing(view)["zoom"] > z, "and in as they close")
	check(s.framing(view)["zoom"] <= 1.0, "never past 1:1")


func test_combat_mode_enters_and_exits_inside_the_scene() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	check(main.get_node_or_null("Combat") != null and main.get_node_or_null("Combat").get_script() == CombatView, "the scene has the combat view")
	main.free()
	# The nodes are wired by hand, as in test_build_mode.gd (no scene tree in the test runner).
	var sim := ShipSim.new()
	var build := BuildMode.new()
	build.sim = sim
	var view := CombatView.new()
	view.sim = sim
	view.build = build
	var key := InputEventKey.new()
	key.keycode = KEY_K
	key.pressed = true
	view._unhandled_input(key)
	check(not view.active, "K in build mode does nothing")
	check(build.message != "", "but it says why")
	build.build_on = false
	view._unhandled_input(key)
	check(view.active, "K in play mode starts the fight")
	check(build.combat and not build.visible, "the interior is put away")
	eq(sim.ships.size(), 2, "the pirate joined the simulation")
	eq(sim.ships[1].name, "Pirate Raider", "it is the pirate")
	near(view.session.distance(), 1800.0, "1800 px ahead")
	for i in 90:
		view.frame(1.0 / 60.0)
	check(view.session.arena.tick >= 85, "the fight runs")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	view._unhandled_input(esc)
	check(view.active, "Esc is refused while the pirate is near and alive")
	check(view._note != "", "with a reason")
	var r := InputEventKey.new()
	r.keycode = KEY_R
	r.pressed = true
	view._unhandled_input(r)
	check(view.active, "R does nothing while you fly")
	view.session.arena.wreck(Session.ENEMY)
	view.frame(1.0 / 60.0)
	view._unhandled_input(esc)
	check(not view.active, "Esc leaves once the pirate is wrecked")
	check(not build.combat and build.visible, "the interior is back")
	eq(sim.ships.size(), 1, "the pirate is gone")
	# Again, and lose.
	view._unhandled_input(key)
	check(view.active, "a second fight")
	view.session.arena.wreck(Session.PLAYER)
	view.frame(1.0 / 60.0)
	view._unhandled_input(r)
	check(not view.active, "R after losing leaves combat")
	check(build.build_on, "in build mode")
	eq(sim.ships.size(), 1, "pirate gone")
	eq(sim.player_ship().components.instances.size(), 0, "with the starter ship reloaded")
	view.free()
	build.free()
	sim.free()
