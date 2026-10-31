extends "res://tests/base_test.gd"
## Enemy morale (scripts/combat/morale.gd, data/morale.json), driven through the real arena and session: the
## break at 35% hull or with no weapon able to fire, the styles' weights, surrender (the enemy holds fire, Y
## spares it, a hit refuses), flight (the 15 s jump spool and what holds it), capture (all crew down for 3 s),
## the hollow that never yields, determinism per seed, and the combat view's Y key and result.

const BuildMode = preload("res://scripts/build/build_mode.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Morale = preload("res://scripts/combat/morale.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const PIRATE := "res://data/ships/pirate_raider.json"
const COURIER := "res://data/ships/starter_courier.json"


## A fight: the pirate (player, hull made huge so the enemy's fire never ends the scenario, turrets on hold) against `design`.
func _session(seed_value := 3, design := PIRATE) -> Session:
	var s := Session.new()
	s.start(Session.load_ship(PIRATE), Session.load_ship(design), seed_value)
	var me = s.arena.ships[Session.PLAYER]
	me.hull_max = 1.0e5
	me.hull = 1.0e5
	s.arena.autofire[Session.PLAYER] = false  # the player's turret would wear the small enemy hull down on its own
	return s


## Swap the session's morale for one with a style of these weights (a Dictionary of surrender, flee, fight) and a cfg tweak.
func _style(s: Session, weights: Dictionary, tweak := {}) -> void:
	var cfg := Morale.config().duplicate(true)
	cfg["styles"]["test"] = weights
	cfg.merge(tweak, true)
	s.morale = Morale.new(s.arena, Session.ENEMY, Session.PLAYER, "test", cfg)
	s.ai.morale = s.morale


func _run(s: Session, seconds: float) -> void:
	for i in int(round(seconds * 60.0)):
		s.tick(Session.STEP)


func _foe(s: Session):
	return s.arena.ships[Session.ENEMY]


func _hurt(s: Session, fraction: float) -> void:
	_foe(s).hull = fraction * _foe(s).hull_max


func _shots(s: Session, idx: int) -> int:
	return s.arena.events.filter(func(e): return e["type"] == "shot" and e["ship"] == idx).size()


## The uids of the parts of `family` of ship `idx` (the enemy's by default).
func _parts(s: Session, family: String, idx := Session.ENEMY) -> Array:
	var comps = s.arena.ships[idx].ship.components
	return comps.instances.keys().filter(func(u): return comps.def(comps.instances[u]["id"]).get("family", "") == family)


func _set_status(s: Session, uids: Array, status: String, idx := Session.ENEMY) -> void:
	for u in uids:
		var inst: Dictionary = s.arena.ships[idx].ship.components.instances[u]
		inst["status"] = status
		inst["hp"] = 0 if status == "disabled" else 5
	s.arena.ships[idx].dirty = true


## `n` crew members (all on their feet) for ship `idx`; the arena alone spawns none.
func _crew_of(s: Session, idx: int, n: int) -> Array:
	var list := []
	for i in n:
		list.append(CrewMember.new("Hand%d" % i))
	s.arena.ships[idx].ship.crew = list
	return list


# --- the break ---------------------------------------------------------------------------------------------

func test_it_breaks_at_35_percent_hull_and_not_before() -> void:
	var s := _session()
	eq(s.morale.state, "steady", "a fresh fight")
	_hurt(s, 0.36)
	_run(s, 1.0)
	eq(s.morale.state, "steady", "36% hull is no break")
	eq(s.morale.rolls, 0, "and nothing was rolled")
	_hurt(s, 0.35)
	_run(s, 0.1)
	check(s.morale.state != "steady", "35% hull breaks it: " + s.morale.state)
	eq(s.morale.rolls, 1, "with one roll")


func test_it_rolls_once_per_fight() -> void:
	var s := _session()
	_style(s, {"surrender": 0.0, "flee": 0.0, "fight": 1.0})
	_hurt(s, 0.3)
	_run(s, 0.1)
	eq(s.morale.state, "fighting_on", "a fight-weighted roll: it fights to the end")
	eq(s.morale.rolls, 1, "rolled")
	_hurt(s, 0.1)
	_run(s, 2.0)
	eq(s.morale.rolls, 1, "morale never triggers again")
	eq(s.morale.state, "fighting_on", "still fighting on")
	eq(s.morale.pilot_mode(), "", "the pilot flies and shoots as before")


func test_no_weapon_able_to_fire_for_5_s_breaks_it_at_full_hull() -> void:
	var s := _session()
	_set_status(s, _parts(s, "weapon"), "disabled")
	_run(s, 4.5)
	eq(s.morale.state, "steady", "4.5 s without a weapon is not enough")
	_run(s, 0.8)
	check(s.morale.state != "steady", "5 s is: " + s.morale.state)
	var t := _session()
	_set_status(t, _parts(t, "weapon"), "disabled")
	_run(t, 3.0)
	_set_status(t, _parts(t, "weapon"), "ok")  # a crew member got one going again
	_run(t, 4.0)
	eq(t.morale.state, "steady", "the count starts over when a weapon works")


func test_a_weapon_without_ammo_cannot_fire() -> void:
	var s := _session(3, "res://data/ships/rustfang_rammer.json")  # its one weapon eats scrap
	check(s.morale._can_shoot(), "the bolt thrower has its scrap")
	var inv = _foe(s).ship.inventory
	inv.spend({"scrap": inv.count("scrap")})
	check(not s.morale._can_shoot(), "no scrap, no bolt thrower: the rammer is unarmed")


# --- the styles -------------------------------------------------------------------------------------------

func test_the_styles_weights_come_from_the_data() -> void:
	var s := _session()
	var cfg := Morale.config()
	var want := {
		"default": {"surrender": 0.4, "flee": 0.4, "fight": 0.2}, "rustfang": {"surrender": 0.5, "flee": 0.3, "fight": 0.2},
		"ram": {"surrender": 0.0, "flee": 0.4, "fight": 0.6}, "concord": {"surrender": 0.2, "flee": 0.6, "fight": 0.2},
		"hollow": {"surrender": 0.0, "flee": 0.0, "fight": 1.0}, "no such style": {"surrender": 0.4, "flee": 0.4, "fight": 0.2},
	}
	for style in want:
		eq(Morale.new(s.arena, Session.ENEMY, Session.PLAYER, style, cfg).weights(), want[style], "weights of " + style)
	eq(s.morale.style, "rustfang", "the pirate raider picks the Rustfang style")
	eq(_session(3, "res://data/ships/rustfang_rammer.json").morale.style, "ram", "the rammer picks ram")
	eq(_session(3, COURIER).morale.style, "default", "a design with no morale entry uses the default")
	check(cfg["break_hull"] == 0.35 and cfg["unarmed_s"] == 5.0 and cfg["offer_s"] == 12.0 and cfg["spool_s"] == 15.0 and cfg["captured_s"] == 3.0, "the numbers of the design")


func test_the_roll_follows_the_weights() -> void:
	var s := _session()
	var count := {"surrender": 0, "flee": 0, "fight": 0}
	var m := Morale.new(s.arena, Session.ENEMY, Session.PLAYER, "rustfang", Morale.config())
	for i in 3000:
		count[m.roll_style()] += 1
	for k in {"surrender": 0.5, "flee": 0.3, "fight": 0.2}:
		var want: float = {"surrender": 0.5, "flee": 0.3, "fight": 0.2}[k]
		check(absf(count[k] / 3000.0 - want) < 0.04, "rustfang %s: %s of 3000" % [k, count[k]])
	var ram := Morale.new(s.arena, Session.ENEMY, Session.PLAYER, "ram", Morale.config())
	var hollow := Morale.new(s.arena, Session.ENEMY, Session.PLAYER, "hollow", Morale.config())
	var ram_surrenders := 0
	var hollow_yields := 0
	for i in 2000:
		ram_surrenders += int(ram.roll_style() == "surrender")
		hollow_yields += int(hollow.roll_style() != "fight")
	eq(ram_surrenders, 0, "a rammer never surrenders")
	eq(hollow_yields, 0, "the hollow never surrenders or flees")


func test_the_hollow_fights_on_whatever_the_seed() -> void:
	for seed_value in 8:
		var s := _session(seed_value + 1)
		s.morale = Morale.new(s.arena, Session.ENEMY, Session.PLAYER, "hollow", Morale.config())
		s.ai.morale = s.morale
		_hurt(s, 0.1)
		_run(s, 0.2)
		eq(s.morale.state, "fighting_on", "seed %d: the hollow fights on" % (seed_value + 1))


# --- surrender --------------------------------------------------------------------------------------------

func test_a_surrendering_enemy_holds_fire_and_y_spares_it() -> void:
	var control := _session()
	_style(control, {"surrender": 0.0, "flee": 0.0, "fight": 1.0})
	_hurt(control, 0.3)
	_run(control, 0.1)
	var before := _shots(control, Session.ENEMY)
	_run(control, 5.0)
	check(_shots(control, Session.ENEMY) > before, "(control) an enemy that fights on keeps shooting")

	var s := _session()
	_style(s, {"surrender": 1.0, "flee": 0.0, "fight": 0.0})
	s.arena.autofire[Session.PLAYER] = true
	_hurt(s, 0.3)
	_run(s, 0.1)
	eq(s.morale.state, "offering", "it offers")
	eq(s.morale.pilot_mode(), "hold", "the pilot holds")
	var offer: Dictionary = s.morale.offer
	check(offer["credits"] >= 30 and offer["credits"] <= 60, "credits in range: %s" % str(offer))
	check(offer.has("fuel") != offer.has("missile"), "and one extra, fuel or missiles: %s" % str(offer))
	var banner: String = s.morale.banner()
	check(banner.begins_with("The Pirate Raider hails: 'Enough! Take it and let us go.' Offer: %d credits, " % offer["credits"]), "the banner: " + banner)
	check(banner.contains("Y accept / keep firing to refuse (12 s)"), "with the keys and the clock: " + banner)
	var shots := _shots(s, Session.ENEMY)
	_run(s, 3.5)
	eq(_shots(s, Session.ENEMY), shots, "no shot from the enemy (guns and turrets) while it offers")
	eq(_foe(s).input["throttle"], 0.0, "and the throttle is cut")
	eq(s.arena.autofire.get(Session.ENEMY, true), false, "its turret autofire is off")
	eq(s.arena.autofire.get(Session.PLAYER, true), false, "so is yours, or a turret hit would refuse the offer")
	check(s.morale.banner().contains("(9 s)"), "the clock runs down: " + s.morale.banner())
	eq(s.state(), "fighting", "still on")
	eq(s.accept_surrender(), "", "Y accepts")
	eq(s.state(), "spared", "the fight ends spared")
	eq(s.morale.offer, offer, "with the offer kept")
	check(s.end_text().begins_with("Deal struck"), "the end text: " + s.end_text())
	check(s.can_leave(), "Esc works")
	eq(s.accept_surrender(), "The fight is over", "a second Y does nothing")
	shots = _shots(s, Session.ENEMY)
	_run(s, 3.0)
	eq(_shots(s, Session.ENEMY), shots, "it stays quiet")
	eq(s.arena.autofire.get(Session.PLAYER, true), false, "and your turrets leave it alone")


func test_y_with_nothing_on_offer_says_so() -> void:
	var s := _session()
	check(s.accept_surrender() != "", "no offer, no deal")
	eq(s.state(), "fighting", "and the fight goes on")


func test_the_offer_can_carry_one_of_its_intact_parts() -> void:
	var s := _session()
	_style(s, {"surrender": 1.0, "flee": 0.0, "fight": 0.0}, {"offer": {"credits": [10, 10], "extra": [], "part_chance": 1.0}})
	for u in _foe(s).ship.components.instances.keys():
		if _foe(s).ship.components.instances[u]["id"] != "laser_mk1":
			_set_status(s, [u], "disabled")
	_hurt(s, 0.3)
	_run(s, 0.1)
	eq(s.morale.state, "offering", "offering")
	eq(s.morale.offer, {"credits": 10, "laser_mk1": 1}, "the one part still working")
	eq(s.morale.offer_text(), "10 credits, Laser Mk1", "in words")
	var none := _session()
	_style(none, {"surrender": 1.0, "flee": 0.0, "fight": 0.0}, {"offer": {"credits": [10, 10], "extra": [], "part_chance": 0.0}})
	_hurt(none, 0.3)
	_run(none, 0.1)
	eq(none.morale.offer, {"credits": 10}, "with part_chance 0 only credits")


func test_a_hit_during_the_offer_refuses_it() -> void:
	var s := _session()
	_style(s, {"surrender": 1.0, "flee": 0.0, "fight": 0.0})
	s.arena.autofire[Session.PLAYER] = true
	_hurt(s, 0.3)
	_run(s, 0.1)
	eq(s.morale.state, "offering", "offering")
	_run(s, 1.0)
	eq(s.morale.state, "offering", "quiet so far")
	var uid := s.arena.add_mount(Session.PLAYER, "test_bolt", Vector2(31.0, 28.0))
	check(s.arena.fire(Session.PLAYER, uid, _foe(s).flight.pos), "the player fires")
	_run(s, 2.0)
	eq(s.morale.state, "fighting_on", "they take that as a no")
	eq(s.morale.banner(), "They take that as a no", "and say so")
	eq(s.morale.pilot_mode(), "", "the pilot is back")
	eq(s.arena.autofire.get(Session.PLAYER, true), true, "your turrets are as they were")
	eq(s.arena.autofire.get(Session.ENEMY, true), true, "and its turrets fire again")
	_run(s, 5.0)
	eq(s.morale.banner(), "", "the banner goes away")
	eq(s.accept_surrender(), "Nobody is offering anything", "the offer is gone")
	eq(s.morale.rolls, 1, "and morale does not roll again")


func test_a_shot_already_in_flight_when_it_broke_is_no_refusal() -> void:
	var s := _session()
	_style(s, {"surrender": 1.0, "flee": 0.0, "fight": 0.0})
	var uid := s.arena.add_mount(Session.PLAYER, "test_bolt", Vector2(31.0, 28.0))
	check(s.arena.fire(Session.PLAYER, uid, _foe(s).flight.pos), "a bolt is on its way")
	check(s.arena.projectiles.size() > 0, "in flight")
	_hurt(s, 0.3)  # this is what the bolt would have done
	_run(s, 0.05)
	eq(s.morale.state, "offering", "it offers")
	_run(s, 1.5)
	var landed := s.arena.events.filter(func(e): return e["ship"] == Session.ENEMY and e["type"] in ["hit", "shield"])
	check(not landed.is_empty(), "the bolt landed")
	check(s.arena.projectiles.is_empty(), "and nothing is left in flight")
	eq(s.morale.state, "offering", "but the offer stands")
	s.arena.ships[Session.PLAYER].cooldowns.clear()
	check(s.arena.fire(Session.PLAYER, uid, _foe(s).flight.pos), "a new bolt")
	_run(s, 1.5)
	eq(s.morale.state, "fighting_on", "that one is a refusal")


func test_an_offer_nobody_answers_runs_out() -> void:
	var s := _session()
	_style(s, {"surrender": 1.0, "flee": 0.0, "fight": 0.0})
	_hurt(s, 0.3)
	_run(s, 11.5)
	eq(s.morale.state, "offering", "still on the table at 11.5 s")
	_run(s, 1.0)
	eq(s.morale.state, "fighting_on", "gone at 12 s")
	eq(s.morale.banner(), "They take that as a no", "with the banner")
	eq(s.state(), "fighting", "the fight goes on")


# --- flight -----------------------------------------------------------------------------------------------

func test_a_fleeing_enemy_spools_for_15_s_and_is_gone() -> void:
	var s := _session()
	_style(s, {"surrender": 0.0, "flee": 1.0, "fight": 0.0})
	_hurt(s, 0.3)
	_run(s, 0.1)
	eq(s.morale.state, "fleeing", "it runs")
	eq(s.morale.pilot_mode(), "flee", "the pilot burns away")
	eq(s.morale.banner(), "The Pirate Raider is spooling its jump drive! Knock out its engines or helm", "the banner")
	_run(s, 7.0)
	check(s.morale.spool > 6.8 and s.morale.spool < 7.2, "7 s spooled: %s" % str(s.morale.spool))
	check(s.distance() > 1300.0, "and it is pulling away: %d px" % s.distance())
	eq(s.state(), "fighting", "not gone yet")
	_run(s, 7.6)
	eq(s.state(), "fighting", "14.7 s is not enough")
	_run(s, 0.6)
	eq(s.state(), "escaped", "15 s: gone")
	check(s.can_leave(), "Esc works")
	check(s.end_text().begins_with("They got away"), s.end_text())
	check(s.distance() > 10000.0, "far away")
	eq(_foe(s).flight.vel, Vector2.ZERO, "and stopped")
	check(s.arena.events.any(func(e): return e["type"] == "escape"), "with a jump event for the view")
	var f := s.framing(Vector2(1600.0, 900.0))
	_run(s, 2.0)
	eq(s.framing(Vector2(1600.0, 900.0))["center"], s.arena.ships[Session.PLAYER].flight.pos, "the camera is on you alone after a moment")
	check(f["zoom"] > 0.0, "(and framed the jump first)")


func test_the_spool_holds_while_every_engine_is_out() -> void:
	var s := _session()
	_style(s, {"surrender": 0.0, "flee": 1.0, "fight": 0.0})
	_hurt(s, 0.3)
	_run(s, 5.0)
	var charged: float = s.morale.spool
	check(charged > 4.5, "it charges: %s" % str(charged))
	# every engine disabled
	var engines := _parts(s, "engine")
	check(engines.size() >= 1, "(the pirate has engines)")
	_set_status(s, engines, "disabled")
	_run(s, 0.1)
	var held: float = s.morale.spool
	_run(s, 6.0)
	eq(s.morale.spool, held, "disabled engines: the charge holds")
	eq(s.morale.hold(), "engines out", "and says why")
	_set_status(s, engines, "ok")
	_run(s, 1.0)
	check(s.morale.spool > held + 0.9, "repaired: it charges again")
	# every engine's outside half shot out
	for u in engines:
		_foe(s).ship.components.instances[u]["out_hp"] = 0
	_foe(s).dirty = true
	held = s.morale.spool
	_run(s, 4.0)
	eq(s.morale.spool, held, "nozzles shot off: the charge holds")
	for u in engines:
		_foe(s).ship.components.instances[u]["out_hp"] = 5
	_foe(s).dirty = true
	# no power: both reactors out
	held = s.morale.spool
	_set_status(s, _parts(s, "reactor"), "disabled")
	_run(s, 4.0)
	eq(s.morale.spool, held, "no power: the charge holds")


func test_the_spool_ignores_who_stands_at_the_helm() -> void:
	var s := _session()
	_style(s, {"surrender": 0.0, "flee": 1.0, "fight": 0.0})
	_hurt(s, 0.3)
	_run(s, 3.0)
	var charged: float = s.morale.spool
	check(charged > 2.5, "it charges: %s" % str(charged))
	_foe(s).ship.manned.clear()  # the crew wandered off to fix a jam
	_run(s, 2.0)
	check(s.morale.spool > charged + 1.9, "an unmanned helm does not hold the charge")
	eq(s.morale.hold(), "", "nothing holds it")
	_foe(s).ship.manned[_parts(s, "helm")[0]] = "Grub"
	_run(s, 1.0)
	check(s.morale.spool > charged + 2.9, "and a manned one does not speed it up")


func test_the_spool_holds_while_the_helm_is_down() -> void:
	var s := _session()
	_style(s, {"surrender": 0.0, "flee": 1.0, "fight": 0.0})
	_hurt(s, 0.3)
	_run(s, 3.0)
	var held: float = s.morale.spool
	check(held > 2.5, "it charges: %s" % str(held))
	var helm := _parts(s, "helm")
	_set_status(s, helm, "disabled")
	_run(s, 4.0)
	eq(s.morale.spool, held, "a disabled helm: the charge holds")
	eq(s.morale.hold(), "helm down", "and says why")
	_set_status(s, helm, "ok")
	_run(s, 1.0)
	check(s.morale.spool > held + 0.9, "repaired: it goes on")


func test_the_spool_holds_while_every_crew_member_is_down() -> void:
	var s := _session()
	_style(s, {"surrender": 0.0, "flee": 1.0, "fight": 0.0})
	var crew := _crew_of(s, Session.ENEMY, 2)
	_hurt(s, 0.3)
	_run(s, 3.0)
	var held: float = s.morale.spool
	check(held > 2.5, "it charges: %s" % str(held))
	crew[0].hp = 0.0
	_run(s, 1.0)
	check(s.morale.spool > held + 0.9, "one crew member down: it charges")
	held = s.morale.spool
	crew[1].hp = 0.0
	_run(s, 2.0)  # (3 s of this would be a capture)
	eq(s.morale.spool, held, "every crew member down: the charge holds")
	eq(s.morale.hold(), "no crew", "and says why")
	crew[1].hp = 30.0
	_run(s, 1.0)
	check(s.morale.spool > held + 0.9, "one is up again: it goes on")


## Morale.spool_hold is one rule for both ships: the same reasons, for the enemy's flight and the player's J.
func test_spool_hold_reasons_for_both_sides() -> void:
	for idx in [Session.PLAYER, Session.ENEMY]:
		var tag := "ship %d" % idx
		var s := _session()
		var co = s.arena.ships[idx]
		eq(Morale.spool_hold(s.arena, idx), "", tag + ": free to charge")
		# engines out: disabled, a nozzle shot off, no power
		var engines := _parts(s, "engine", idx)
		check(engines.size() >= 1, tag + ": (has engines)")
		_set_status(s, engines.slice(0, 1), "disabled", idx)
		eq(Morale.spool_hold(s.arena, idx), "", tag + ": one engine out of two: free")
		_set_status(s, engines, "disabled", idx)
		eq(Morale.spool_hold(s.arena, idx), "engines out", tag + ": every engine disabled")
		_set_status(s, engines, "ok", idx)
		for u in engines:
			co.ship.components.instances[u]["out_hp"] = 0
		eq(Morale.spool_hold(s.arena, idx), "engines out", tag + ": every nozzle shot off (offline)")
		for u in engines:
			co.ship.components.instances[u]["out_hp"] = 5
		eq(Morale.spool_hold(s.arena, idx), "", tag + ": nozzles back")
		for u in engines:
			co.powered[u] = false
		eq(Morale.spool_hold(s.arena, idx), "engines out", tag + ": every engine unpowered")
		for u in engines:
			co.powered[u] = true
		# helm down: disabled, unpowered, none at all
		var helm := _parts(s, "helm", idx)
		_set_status(s, helm, "disabled", idx)
		eq(Morale.spool_hold(s.arena, idx), "helm down", tag + ": helm disabled")
		_set_status(s, helm, "ok", idx)
		co.powered[helm[0]] = false
		eq(Morale.spool_hold(s.arena, idx), "helm down", tag + ": helm unpowered")
		co.powered[helm[0]] = true
		eq(Morale.spool_hold(s.arena, idx), "", tag + ": helm back")
		var inst: Dictionary = co.ship.components.instances[helm[0]]
		co.ship.components.instances.erase(helm[0])
		eq(Morale.spool_hold(s.arena, idx), "helm down", tag + ": no helm at all")
		co.ship.components.instances[helm[0]] = inst
		# crew: none listed is free; some up is free; all down holds
		eq(Morale.spool_hold(s.arena, idx), "", tag + ": no crew list (none spawned): free")
		var crew := _crew_of(s, idx, 3)
		crew[0].hp = 0.0
		crew[1].hp = 0.0
		eq(Morale.spool_hold(s.arena, idx), "", tag + ": one on their feet: free")
		crew[2].hp = 0.0
		eq(Morale.spool_hold(s.arena, idx), "no crew", tag + ": every crew member down")
		# engines are named first when several things are wrong
		_set_status(s, engines, "disabled", idx)
		eq(Morale.spool_hold(s.arena, idx), "engines out", tag + ": engines come first")


func test_a_fleeing_ship_still_fires_when_its_guns_bear() -> void:
	var s := _session()
	_style(s, {"surrender": 0.0, "flee": 1.0, "fight": 0.0})
	_foe(s).flight.pos = Vector2(0.0, -900.0)
	_hurt(s, 0.3)
	_run(s, 0.1)
	var before := _shots(s, Session.ENEMY)
	_run(s, 4.0)
	check(_shots(s, Session.ENEMY) > before, "its rattle turret covers its stern and keeps shooting")


# --- the player's own jump drive ------------------------------------------------------------------------------

func test_the_players_jump_holds_with_all_engines_disabled_and_resumes() -> void:
	var s := _session()
	eq(s.start_jump(), "", "J starts the spool")
	_run(s, 3.0)
	check(s.jump_charge > 2.9 and s.jump_charge < 3.1, "it charges: %s" % str(s.jump_charge))
	eq(s.jump_hold(), "", "nothing holds it")
	var engines := _parts(s, "engine", Session.PLAYER)
	check(engines.size() >= 2, "(the pirate has two engines)")
	_set_status(s, engines, "disabled", Session.PLAYER)
	_run(s, 0.1)
	var held: float = s.jump_charge
	_run(s, 5.0)
	eq(s.jump_charge, held, "every engine disabled: the spool holds")
	eq(s.jump_hold(), "Jump drive held: engines out", "and says why")
	check(not s.jump_ready() and not s.can_leave(), "so you cannot jump")
	_set_status(s, engines.slice(0, 1), "ok", Session.PLAYER)  # one engine repaired
	_run(s, 1.0)
	check(s.jump_charge > held + 0.9, "one engine back: it resumes")
	eq(s.jump_hold(), "", "and nothing holds it")
	_run(s, 7.0)
	check(s.jump_ready() and s.can_leave(), "and the drive finishes after the whole spool")


func test_the_players_jump_holds_for_a_down_helm_and_for_no_crew() -> void:
	var s := _session()
	s.start_jump()
	_run(s, 2.0)
	var held: float = s.jump_charge
	var helm := _parts(s, "helm", Session.PLAYER)
	_set_status(s, helm, "disabled", Session.PLAYER)
	_run(s, 3.0)
	eq(s.jump_charge, held, "a disabled helm holds the spool")
	eq(s.jump_hold(), "Jump drive held: helm down", "and says why")
	_set_status(s, helm, "ok", Session.PLAYER)
	_run(s, 1.0)
	check(s.jump_charge > held + 0.9, "the helm is back: it resumes")
	held = s.jump_charge
	var crew := _crew_of(s, Session.PLAYER, 2)
	crew[0].hp = 0.0
	_run(s, 1.0)
	check(s.jump_charge > held + 0.9, "one crew member down: it goes on")
	held = s.jump_charge
	crew[1].hp = 0.0
	_run(s, 3.0)
	eq(s.jump_charge, held, "every crew member down: the spool holds")
	eq(s.jump_hold(), "Jump drive held: no crew", "and says why")
	crew[0].hp = 20.0
	_run(s, 1.0)
	check(s.jump_charge > held + 0.9, "somebody gets up: it resumes")


func test_the_view_says_why_the_players_jump_is_held() -> void:
	var made := _view()
	var view: CombatView = made[0]
	var ship = view.session.arena.ships[Session.PLAYER].ship
	check(ship.components.instances.is_empty(), "(the starter ship has no engines at all)")
	view._unhandled_input(_key(KEY_J))
	eq(view._note, "Jump drive held: engines out", "J says it will not charge: " + view._note)
	for i in 60:
		view.frame(1.0 / 60.0)
	eq(view.session.jump_charge, 0.0, "and the spool is on but not charging")
	made[0].free()
	made[1].free()
	made[2].free()


# --- capture ----------------------------------------------------------------------------------------------

func _crew(s: Session, n: int) -> Array:
	return _crew_of(s, Session.ENEMY, n)


func test_all_crew_down_for_3_s_captures_the_ship() -> void:
	var s := _session()
	var crew := _crew(s, 3)
	_run(s, 0.5)
	for m in crew:
		m.hp = 0.0
	_run(s, 2.8)
	eq(s.state(), "fighting", "2.8 s down is not enough")
	_run(s, 0.4)
	eq(s.state(), "captured", "3 s: the ship is yours")
	check(s.end_text().begins_with("Nobody is left standing aboard. She's yours"), s.end_text())
	check(s.can_leave(), "Esc works")
	check(_foe(s).hull > 0.9 * _foe(s).hull_max, "with the hull whole")
	eq(s.morale.pilot_mode(), "stop", "guns and helm stop")
	var shots := _shots(s, Session.ENEMY)
	_run(s, 3.0)
	eq(_shots(s, Session.ENEMY), shots, "no shot from a captured ship")
	eq(_foe(s).input["throttle"], 0.0, "no throttle")
	eq(s.arena.autofire.get(Session.PLAYER, true), false, "and your turrets do not wreck the prize")


func test_a_crew_member_standing_up_in_time_saves_the_ship() -> void:
	var s := _session()
	var crew := _crew(s, 2)
	_run(s, 0.5)
	crew[0].hp = 0.0
	crew[1].hp = 0.0
	_run(s, 2.5)
	crew[1].hp = 40.0  # a crewmate got Hand1 up
	_run(s, 2.0)
	eq(s.state(), "fighting", "one on their feet: no capture")
	crew[1].hp = 0.0
	_run(s, 2.5)
	eq(s.state(), "fighting", "and the 3 s start over")
	_run(s, 0.6)
	eq(s.state(), "captured", "3 s after the last one went down")


func test_a_ship_that_started_with_no_crew_is_never_captured() -> void:
	var s := _session()
	eq(_foe(s).ship.crew.size(), 0, "(the arena alone spawns no crew)")
	_run(s, 10.0)
	eq(s.morale.state, "steady", "an empty crew list is not a captured crew")
	eq(s.state(), "fighting", "still fighting")


func test_an_empty_crew_list_after_crew_counts_as_all_down() -> void:
	var s := _session()
	_crew(s, 2)
	_run(s, 0.5)
	_foe(s).ship.crew = []
	_run(s, 3.2)
	eq(s.state(), "captured", "nobody left aboard")


func test_capture_beats_an_offer_and_a_flight() -> void:
	for weights in [{"surrender": 1.0, "flee": 0.0, "fight": 0.0}, {"surrender": 0.0, "flee": 1.0, "fight": 0.0}]:
		var s := _session()
		_style(s, weights)
		var crew := _crew(s, 2)
		_run(s, 0.5)
		_hurt(s, 0.3)
		_run(s, 1.0)
		check(s.morale.state in ["offering", "fleeing"], "broken first: " + s.morale.state)
		for m in crew:
			m.hp = 0.0
		_run(s, 3.2)
		eq(s.state(), "captured", "then captured from %s" % str(weights))


func test_lost_wins_over_every_morale_state() -> void:
	var s := _session()
	_style(s, {"surrender": 1.0, "flee": 0.0, "fight": 0.0})
	_hurt(s, 0.3)
	_run(s, 0.1)
	s.accept_surrender()
	eq(s.state(), "spared", "spared")
	s.arena.wreck(Session.PLAYER)
	eq(s.state(), "lost", "and then you are wrecked: lost")
	var t := _session()
	t.arena.wreck(Session.ENEMY)
	eq(t.state(), "won", "a wrecked enemy is a win")
	check(t.can_leave(), "and Esc works")


# --- determinism ------------------------------------------------------------------------------------------

func _outcome(seed_value: int) -> Session:
	var s := _session(seed_value)
	_hurt(s, 0.3)
	_run(s, 4.0)
	return s


func test_the_same_seed_gives_the_same_morale() -> void:
	var states := {}
	for seed_value in range(1, 13):
		var a := _outcome(seed_value)
		var b := _outcome(seed_value)
		eq(a.morale.state, b.morale.state, "seed %d: state" % seed_value)
		eq(a.morale.offer, b.morale.offer, "seed %d: offer" % seed_value)
		eq(a.morale.spool, b.morale.spool, "seed %d: spool" % seed_value)
		eq(a.arena.snapshot(), b.arena.snapshot(), "seed %d: the whole arena" % seed_value)
		states[a.morale.state] = true
	check(states.size() >= 2, "different seeds roll different endings: %s" % str(states.keys()))


# --- the combat view --------------------------------------------------------------------------------------

func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k


## A combat view in a fight with the pirate, wired by hand like test_combat_session.gd.
func _view() -> Array:
	var sim := ShipSim.new()
	var build := BuildMode.new()
	build.sim = sim
	build.build_on = false
	var view := CombatView.new()
	view.sim = sim
	view.build = build
	_fight(view)
	return [view, build, sim]


## K, and the player's hull made huge so the enemy's fire does not end the scenario.
func _fight(view: CombatView) -> void:
	view._unhandled_input(_key(KEY_K))
	var me = view.session.arena.ships[Session.PLAYER]
	me.hull_max = 1.0e5
	me.hull = 1.0e5


func test_the_view_takes_y_and_hands_the_offer_to_the_map() -> void:
	var made := _view()
	var view: CombatView = made[0]
	check(view.active, "a fight")
	_style(view.session, {"surrender": 1.0, "flee": 0.0, "fight": 0.0})
	view._unhandled_input(_key(KEY_Y))
	check(view._note.contains("Nobody is offering"), "Y with nothing offered says so: " + view._note)
	var foe = view.session.arena.ships[Session.ENEMY]
	foe.hull = 0.3 * foe.hull_max
	for i in 6:
		view.frame(1.0 / 60.0)
	eq(view.session.morale.state, "offering", "it offers")
	var got := []
	view.finished.connect(func(r): got.append(r))
	var offer: Dictionary = view.session.morale.offer.duplicate()
	view._unhandled_input(_key(KEY_Y))
	eq(view.session.state(), "spared", "Y took the deal")
	view._unhandled_input(_key(KEY_ESCAPE))
	check(not view.active, "Esc leaves")
	eq(got.size(), 1, "the map was told")
	eq(got[0]["state"], "spared", "state spared")
	eq(got[0]["offer"], offer, "with the offer")
	check(got[0].has("enemy") and got[0].has("hull") and got[0].has("hull_max"), "and the usual keys")
	made[0].free()
	made[1].free()
	made[2].free()


func test_the_view_results_for_the_other_endings() -> void:
	var made := _view()
	var view: CombatView = made[0]
	var got := []
	view.finished.connect(func(r): got.append(r))
	# captured
	var crew := _crew(view.session, 2)
	view.frame(1.0 / 60.0)
	for m in crew:
		m.hp = 0.0
	for i in 200:
		view.frame(1.0 / 60.0)
	eq(view.session.state(), "captured", "captured in the view")
	view._unhandled_input(_key(KEY_ESCAPE))
	eq(got[0]["state"], "captured", "result: captured")
	check(not got[0].has("offer"), "and no offer")
	# escaped
	_fight(view)
	_style(view.session, {"surrender": 0.0, "flee": 1.0, "fight": 0.0})
	var foe = view.session.arena.ships[Session.ENEMY]
	foe.hull = 0.3 * foe.hull_max
	for i in 60 * 16:
		view.frame(1.0 / 60.0)
		if view.session.state() != "fighting":
			break
	eq(view.session.state(), "escaped", "escaped in the view")
	view._unhandled_input(_key(KEY_ESCAPE))
	eq(got[1]["state"], "escaped", "result: escaped")
	# fled: the player's own jump drive while the enemy is still there
	_fight(view)
	view.session.jump_charge = Session.JUMP_SPOOL
	view.frame(1.0 / 60.0)
	check(not view.active, "the jump drive took us away")
	eq(got[2]["state"], "fled", "result: fled")
	made[0].free()
	made[1].free()
	made[2].free()
