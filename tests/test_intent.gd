extends "res://tests/base_test.gd"
## Enemy intent on the player's schematic (scripts/combat/intent.gd, data/combat_ui.json): the part the pilot aims
## at (held for at least 0.5 s), the heavy enemy weapons about to fire with their true eta, nothing once a ship is
## wrecked or the enemy holds fire, and the schematic's layout of it. Driven through the real arena and session.

const Intent = preload("res://scripts/combat/intent.gd")
const Schematic = preload("res://scripts/ui/schematic.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const PIRATE := "res://data/ships/pirate_raider.json"
const REACTOR := 5  ## uids of the pirate raider's parts
const LASER := 1


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, want, got])


func _session() -> Session:
	var s := Session.new()
	s.start(Session.load_ship(PIRATE), Session.load_ship(PIRATE), 3)
	return s


func _of(s: Session) -> Dictionary:
	return Intent.of(s.arena, s.ai, Session.PLAYER)


## An Artemis (heavy: a missile) on the enemy with 3 missiles; returns its mount uid.
func _artemis(s: Session) -> int:
	s.arena.ships[Session.ENEMY].ship.inventory.add("missile", 3)
	return s.arena.add_mount(Session.ENEMY, "artemis_mk1", Vector2(30.0, 20.0))


## The Artemis is ready in `seconds`.
func _ready_in(s: Session, uid: int, seconds: float) -> void:
	s.arena.ships[Session.ENEMY].cooldowns[uid] = s.arena.tick + roundi(seconds * 60.0)


func test_the_numbers_are_in_the_data_file() -> void:
	var cfg := Intent.config()
	near(float(cfg["warn_s"]), 1.5, "warns 1.5 s ahead")
	near(float(cfg["heavy_damage"]), 3.0, "heavy from damage 3")
	near(float(cfg["hold_s"]), 0.5, "a target is held 0.5 s")
	near(float(cfg["min_cooldown"]), 3.0, "a warned gun takes at least 3 s to reload")
	eq(cfg["heavy_kinds"], ["missile", "beam"], "missiles and beams are heavy")
	eq(cfg["heavy_damage_types"], ["ion"], "ion is heavy")
	check(str(JSON.parse_string(FileAccess.get_file_as_string(Intent.CONFIG_PATH)).get("_doc", "")) != "", "the file explains itself")


# --- the target ---------------------------------------------------------------------------------------

func test_it_names_the_part_the_pilot_picks() -> void:
	var s := _session()
	check(s.ai.pick_target() >= 0, "the pirate has something to aim at")
	s.ai.target_uid = s.ai.pick_target()
	var i := _of(s)
	eq(i["target_uid"], s.ai.pick_target(), "the part pick_target picks")
	eq(i["target_family"], "weapon", "a weapon, the first family it shoots")
	eq(i["target_uid"], LASER, "the nearest one: the laser")
	s.ai.target_uid = REACTOR
	s.arena.step(1.0)
	eq(_of(s)["target_family"], "reactor", "and later its next choice")
	s.ai.target_uid = -1
	s.arena.step(1.0)
	eq(_of(s)["target_uid"], -1, "no target: none (the pilot aims at the centre)")
	eq(_of(s)["target_family"], "", "and no family")


func test_the_pilot_really_aims_somewhere_in_a_fight() -> void:
	var s := _session()
	for k in 30:
		s.tick(Session.STEP)
	eq(_of(s)["target_uid"], s.ai.target_uid, "after the pilot has thought, intent matches it")
	check(int(_of(s)["target_uid"]) >= 0, "and it is a part")


func test_a_new_target_waits_half_a_second() -> void:
	var s := _session()
	s.ai.target_uid = LASER
	eq(_of(s)["target_uid"], LASER, "shown at once the first time")
	s.ai.target_uid = REACTOR  # the pilot flickers to another part
	eq(_of(s)["target_uid"], LASER, "the old target stays at first")
	s.arena.step(0.3)
	eq(_of(s)["target_uid"], LASER, "still after 0.3 s")
	s.arena.step(0.3)
	eq(_of(s)["target_uid"], REACTOR, "and the new one after 0.5 s")
	s.ai.target_uid = LASER
	s.arena.step(0.2)
	eq(_of(s)["target_uid"], REACTOR, "the new one is held in its turn")
	s.arena.step(0.4)
	eq(_of(s)["target_uid"], LASER, "and then it goes back")


func test_a_part_that_is_gone_is_dropped_at_once() -> void:
	var s := _session()
	s.ai.target_uid = REACTOR
	eq(_of(s)["target_uid"], REACTOR, "shown")
	var inst: Dictionary = s.arena.ships[Session.PLAYER].ship.components.instances[REACTOR]
	inst["status"] = "disabled"
	inst["hp"] = 0
	eq(_of(s)["target_uid"], -1, "a disabled part is no longer marked, even before the pilot notices")
	s.ai.target_uid = LASER
	eq(_of(s)["target_uid"], LASER, "the pilot's new choice shows at once, without waiting")


func test_the_hold_is_the_same_whenever_it_is_asked() -> void:
	var s := _session()
	s.ai.target_uid = LASER
	var a := _of(s)
	var b := _of(s)
	eq(a, b, "asking twice in a tick changes nothing")
	s.ai.target_uid = REACTOR
	s.arena.step(0.2)
	eq([_of(s)["target_uid"], _of(s)["target_uid"]], [LASER, LASER], "nor does asking often")


# --- heavy weapons ------------------------------------------------------------------------------------

func test_what_is_heavy() -> void:
	var w := Weapons.new()
	for id in ["artemis_mk1", "test_missile", "bolt_thrower_scrap", "heat_lance_neon", "ion_blast_mk1", "siren_ion_neon"]:
		check(Intent.is_heavy(w.def(id)), id + " is heavy (a missile, a beam or ion)")
	check(Intent.is_heavy(w.def("pulse_mk2")), "damage 3 is heavy")
	for id in ["laser_mk1", "pulse_mk1", "test_bolt", "test_flak", "laser_turret_mk1", "rattle_burst_scrap", "shrapnel_cannon_scrap", "breach_harpoon", "leech_laser"]:
		check(not Intent.is_heavy(w.def(id)), id + " is light")


func test_a_heavy_weapon_shows_only_inside_the_warning_with_its_true_eta() -> void:
	var s := _session()
	var uid := _artemis(s)
	_ready_in(s, uid, 2.0)
	eq(_of(s)["heavy"], [], "2 s out: not yet")
	_ready_in(s, uid, 1.6)
	eq(_of(s)["heavy"], [], "1.6 s out: not yet")
	_ready_in(s, uid, 1.5)
	var h: Array = _of(s)["heavy"]
	eq(h.size(), 1, "1.5 s out: it shows")
	eq(h[0]["uid"], uid, "that weapon")
	eq(h[0]["name"], "Artemis Mk1", "by its name")
	near(h[0]["eta"], 1.5, "with its cooldown left")
	_ready_in(s, uid, 0.8)
	near(_of(s)["heavy"][0]["eta"], 0.8, "0.8 s")
	s.arena.step(0.5)
	near(_of(s)["heavy"][0]["eta"], 0.3, "and 0.5 s later 0.3 s")
	s.arena.step(1.0)
	near(_of(s)["heavy"][0]["eta"], 0.0, "ready")
	eq(_of(s)["heavy"].size(), 1, "a ready weapon still shows (it fires as soon as it can bear)")


func test_a_heavy_gun_that_fires_faster_than_you_can_react_never_shows() -> void:
	var w := Weapons.new()
	for id in ["laser_mk2", "pulse_mk2"]:
		check(float(w.def(id)["damage"]) >= 3.0 and float(w.def(id)["cooldown"]) < 3.0, id + " hits hard but reloads inside 3 s")
		check(not Intent.warns(w.def(id)), id + " earns no row")
	for id in ["artemis_mk1", "test_missile", "heat_lance_neon", "ion_blast_mk1", "siren_ion_neon", "bolt_thrower_scrap"]:
		check(Intent.warns(w.def(id)), id + " earns a row (3 s or more)")
	var s := _session()
	var foe = s.arena.ships[Session.ENEMY]
	s.arena.weapons.defs["fast_missile"] = {"kind": "missile", "damage": 4, "cooldown": 1.3, "range": 1200}
	var fast := [s.arena.add_mount(Session.ENEMY, "pulse_mk2", Vector2(20.0, 20.0)), s.arena.add_mount(Session.ENEMY, "laser_mk2", Vector2(22.0, 20.0)), s.arena.add_mount(Session.ENEMY, "fast_missile", Vector2(24.0, 20.0))]
	foe.ship.inventory.add("missile", 9)
	for u in fast:
		foe.cooldowns[u] = s.arena.tick + 60  # ready in 1 s: inside the warning
	eq(_of(s)["heavy"], [], "heavy guns with a 1.3 s cooldown or less: no row, even a missile")
	for u in fast:
		foe.cooldowns[u] = 0
	eq(_of(s)["heavy"], [], "nor when they are ready")
	var art := _artemis(s)
	_ready_in(s, art, 1.0)
	eq(_of(s)["heavy"].map(func(h): return h["uid"]), [art], "the Artemis still does")
	s.arena.weapons.defs["fast_missile"]["cooldown"] = 3.0
	eq(_of(s)["heavy"].size(), 2, "and a gun with a 3 s cooldown (the line) is warned about too")


func test_a_heavy_weapon_that_cannot_fire_does_not_show() -> void:
	var s := _session()
	var uid := _artemis(s)
	var foe = s.arena.ships[Session.ENEMY]
	foe.mounts[uid]["powered"] = false
	eq(_of(s)["heavy"], [], "no power")
	foe.mounts[uid]["powered"] = true
	eq(_of(s)["heavy"].size(), 1, "power back")
	foe.mounts[uid]["jammed"] = true
	eq(_of(s)["heavy"], [], "jammed")
	foe.mounts[uid].erase("jammed")
	foe.ship.inventory.add("missile", -3)
	eq(_of(s)["heavy"], [], "no missiles")


func test_a_light_laser_never_shows() -> void:
	var s := _session()
	var foe = s.arena.ships[Session.ENEMY]
	check(foe.mounts.size() >= 2, "the pirate has its laser and its turret")
	for uid in foe.mounts:
		foe.cooldowns[uid] = 0
	eq(_of(s)["heavy"], [], "ready lasers and turrets are not heavy")
	for k in 120:
		s.tick(Session.STEP)
		eq(_of(s)["heavy"], [], "nor while the fight runs")
	var uid := _artemis(s)
	_ready_in(s, uid, 1.0)
	eq(_of(s)["heavy"].map(func(h): return h["uid"]), [uid], "only the Artemis, next to them")


func test_heavy_weapons_come_in_uid_order() -> void:
	var s := _session()
	var a := _artemis(s)
	var b := s.arena.add_mount(Session.ENEMY, "heat_lance_neon", Vector2(20.0, 20.0))
	_ready_in(s, a, 1.0)
	_ready_in(s, b, 0.4)
	eq(_of(s)["heavy"].map(func(h): return h["uid"]), [b, a], "uid order (negative uids sort first), not eta order, so rows keep their place")


# --- when nothing shows ---------------------------------------------------------------------------------

func test_nothing_shows_once_the_enemy_is_wrecked() -> void:
	var s := _session()
	var uid := _artemis(s)
	_ready_in(s, uid, 0.5)
	s.ai.target_uid = LASER
	eq(_of(s)["heavy"].size(), 1, "armed")
	s.arena.wreck(Session.ENEMY)
	eq(_of(s), Intent.empty(), "a wreck aims at nothing")
	eq(_of(s)["target_uid"], -1, "no target")


func test_nothing_shows_once_the_player_is_wrecked() -> void:
	var s := _session()
	s.ai.target_uid = LASER
	s.arena.wreck(Session.PLAYER)
	eq(_of(s), Intent.empty(), "there is nothing left to aim at")


func test_nothing_shows_while_the_enemy_surrenders() -> void:
	var s := _session()
	var uid := _artemis(s)
	_ready_in(s, uid, 0.5)
	s.ai.target_uid = LASER
	s.morale.state = "offering"
	eq(_of(s), Intent.empty(), "a surrendering enemy holds fire")
	s.morale.state = "fleeing"
	eq(_of(s)["heavy"].size(), 1, "a fleeing one still fires when its guns bear")
	s.morale.state = "captured"
	eq(_of(s), Intent.empty(), "a captured ship does nothing")


# --- the schematic ------------------------------------------------------------------------------------------

func test_short_names_and_family_lines() -> void:
	eq(Intent.short_name("Artemis Mk1"), "Artemis", "the mark goes")
	eq(Intent.short_name("Laser Turret Mk1"), "Laser Turret", "whatever the name")
	eq(Intent.short_name("Helm"), "Helm", "no mark, no change")
	eq(Intent.short_name("Mk1"), "Mk1", "a name that is only a mark stays")
	eq(Intent.family_label("weapon"), "Weapons", "weapon")
	eq(Intent.family_label("reactor"), "Reactor", "reactor")
	eq(Intent.family_label("zzz"), "Zzz", "an unlisted family is capitalised")


func test_the_schematic_lays_out_the_reticle_and_the_rows() -> void:
	var s := _session()
	var uid := _artemis(s)
	_ready_in(s, uid, 0.8)
	s.ai.target_uid = LASER
	var ship = s.arena.ships[Session.PLAYER].ship
	var map := {"origin": Vector2(8.0, 26.0), "s": 6.0}
	var lay := Schematic.intent_layout(ship, _of(s), map)
	eq(lay["line"], "Targeting: Weapons", "the line under the map")
	eq(lay["rows"], [{"text": "Artemis in 0.8 s", "hot": false}], "a row for the Artemis")
	var cells: Array = ship.components.instances[LASER]["cells"]
	var c0: Vector2i = cells[0]
	var rect := Rect2(map["origin"] + Vector2(c0) * 6.0, Vector2(6.0, 6.0))
	check(Rect2(rect.position - Vector2(30.0, 30.0), Vector2(60.0, 60.0)).has_point(lay["ring"]), "the reticle sits on the laser's cells")
	check(lay["radius"] >= 3.0, "with a ring around them")
	_ready_in(s, uid, 0.4)
	eq(Schematic.intent_layout(ship, _of(s), map)["rows"], [{"text": "Artemis in 0.4 s", "hot": true}], "red under 0.5 s")
	_ready_in(s, uid, 0.0)
	eq(Schematic.intent_layout(ship, _of(s), map)["rows"], [{"text": "Artemis ready", "hot": true}], "ready")


func test_the_schematic_lays_out_nothing_without_intent() -> void:
	var s := _session()
	var ship = s.arena.ships[Session.PLAYER].ship
	var map := {"origin": Vector2(8.0, 26.0), "s": 6.0}
	for empty in [{}, Intent.empty()]:
		var lay := Schematic.intent_layout(ship, empty, map)
		eq([lay.has("ring"), lay["line"], lay["rows"]], [false, "", []], "nothing to draw for " + str(empty))
	var no_map := Schematic.intent_layout(ship, {"target_uid": LASER, "target_family": "weapon", "heavy": []}, {})
	check(not no_map.has("ring"), "no map, no reticle")


func test_many_heavy_weapons_are_capped() -> void:
	var s := _session()
	var heavy := []
	for k in 6:
		heavy.append({"uid": -k - 1, "name": "Artemis Mk1", "eta": 1.0})
	var ship = s.arena.ships[Session.PLAYER].ship
	var lay := Schematic.intent_layout(ship, {"target_uid": -1, "target_family": "", "heavy": heavy}, {})
	eq(lay["rows"].size(), 5, "4 rows and a '+2 more'")
	eq(lay["rows"][4]["text"], "+2 more", "the rest")
	eq(lay["line"], "", "no target, no line")


## The panel itself, bound to a live fight, with and without intent (it draws on the next frame: here its state is
## checked, and a real draw is exercised by the screenshots).
func test_the_panel_takes_intent_or_none() -> void:
	var s := _session()
	var p := Schematic.new()
	p.bind(s.arena, Session.PLAYER, "Your ship")
	eq(p.intent, {}, "empty by default: it draws as it always did")
	p.intent = _of(s)
	eq(p.intent.keys().size(), 3, "set from Intent.of")
	p.free()
