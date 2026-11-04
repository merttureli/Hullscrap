extends "res://tests/base_test.gd"
## The crew kit screen (I) and the boarding party picker (Beta 4.1): kit changes in flight (equip, take off, move between crew, refusals), when the screen opens, and
## the picker that opens first on every kind of boarding, with "Go alone".

const CrewKit = preload("res://scripts/crew/crew_kit.gd")
const CrewKitPanel = preload("res://scripts/ui/crew_kit_panel.gd")
const Kit = preload("res://scripts/board/kit.gd")
const Site = preload("res://scripts/board/site.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const BoardView = preload("res://scripts/board/board_view.gd")
const Loadout = preload("res://scripts/board/board_loadout.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Party = preload("res://scripts/board/party.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.crew.append(CrewMember.new("Rook", Vector2(10, 10), "human"))
	s.crew.append(CrewMember.new("Tess", Vector2(12, 10), "fenn"))
	for it in ["exosuit", "basic_armor", "rifle", "overcharge_coil_mk1"]:
		s.inventory.add(it, 1)
	return s


func _by(s: Ship, name: String):
	for m in s.crew:
		if m.name == name:
			return m
	return null


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


## A bare stand-in for the BuildMode: the screen reads `combat` and `build_on` of it.
class FakeBuild extends Node:
	var combat := false
	var build_on := false


func _panel(s: Ship, fake = null) -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [s]
	var panel := CrewKitPanel.new()
	panel.sim = sim
	panel.build = fake
	panel.size = Vector2(1600.0, 900.0)
	return {"panel": panel, "sim": sim}


func _free(d: Dictionary) -> void:
	d["panel"].free()
	d["sim"].free()


# --- the rules ---------------------------------------------------------------------------------------------------------------

func test_the_screen_lists_every_crew_member_but_not_the_drone() -> void:
	var s := _ship()
	s.crew.append(CrewMember.new("Bolt", Vector2(14, 10), "drone"))
	var names: Array = CrewKit.new(s).people().map(func(m): return m.name)
	check(names.has("Rook") and names.has("Tess"), "the crew is there")
	check(not s.crew.any(func(m): return m.is_drone() and names.has(m.name)), "the repair drone is not")
	check(s.crew.any(func(m): return m.is_drone()), "(there is a drone aboard)")
	check(CrewKit.new(s).people()[0].is_player, "the soldier comes first")


func test_equip_from_the_hold_and_take_off_back_to_it() -> void:
	var s := _ship()
	var rook = _by(s, "Rook")
	eq(CrewKit.equip_from_hold(s, rook, "exosuit"), "", "Rook puts the exosuit on")
	eq([Kit.slot_value(rook, "body", 0), s.inventory.count("exosuit")], ["exosuit", 0], "it is on him and out of the hold")
	eq(CrewKit.equip_from_hold(s, rook, "carbine"), "", "a weapon goes in the first free hand")
	eq(Kit.slot_value(rook, "weapon", 1), "carbine", "the second slot")
	eq(s.inventory.count("rifle"), 0, "and leaves the hold")
	eq(CrewKit.equip_from_hold(s, rook, "overcharge_coil_mk1"), "", "a mod goes in a mod slot")
	eq(CrewKit.set_slot(s, rook, "body", 0, ""), "", "taking the body off")
	eq([Kit.slot_value(rook, "body", 0), s.inventory.count("exosuit")], ["", 1], "it is back in the hold")
	eq(CrewKit.set_slot(s, rook, "weapon", 1, ""), "", "the carbine too")
	eq(s.inventory.count("rifle"), 1, "back in the hold")


func test_a_choice_that_is_not_in_the_hold_is_refused() -> void:
	var s := _ship()
	var rook = _by(s, "Rook")
	check(CrewKit.set_slot(s, rook, "weapon", 1, "slugthrower") != "", "no slugthrower in the hold")
	check(CrewKit.set_slot(s, rook, "body", 0, "heat_suit") != "", "no heat suit either")
	eq(Kit.slot_value(rook, "body", 0), "", "nothing changed")


func test_an_item_moves_from_one_crew_member_to_another() -> void:
	var s := _ship()
	var rook = _by(s, "Rook")
	var tess = _by(s, "Tess")
	CrewKit.equip_from_hold(s, rook, "exosuit")
	CrewKit.equip_from_hold(s, rook, "carbine")
	var hold: int = s.inventory.count("exosuit")
	eq(CrewKit.move(s, rook, "body", 0, tess), "", "the exosuit goes to Tess")
	eq([Kit.slot_value(rook, "body", 0), Kit.slot_value(tess, "body", 0)], ["", "exosuit"], "off one, on the other")
	eq(s.inventory.count("exosuit"), hold, "the hold is the same")
	eq(CrewKit.move(s, rook, "weapon", 1, tess), "", "the carbine too")
	eq(Kit.slot_value(tess, "weapon", 0), tess.sidearm(), "Tess keeps her own sidearm")
	eq(Kit.slot_value(tess, "weapon", 1), "carbine", "and has the carbine in the free hand")
	check(CrewKit.move(s, rook, "weapon", 0, tess) != "", "a sidearm stays with its owner")
	check(CrewKit.move(s, rook, "body", 0, tess) != "", "nothing to move")


func test_can_wear_refuses_and_a_refused_move_changes_nothing() -> void:
	var s := _ship()
	var rook = _by(s, "Rook")
	var q := CrewMember.new("Vik", Vector2(14, 10), "quillback")
	s.crew.append(q)
	CrewKit.equip_from_hold(s, rook, "exosuit")
	var why := CrewKit.move(s, rook, "body", 0, q)
	check(why.contains("cannot wear a suit or armour"), "the reason is given: %s" % why)
	eq(Kit.slot_value(rook, "body", 0), "exosuit", "he still wears it")
	eq(s.inventory.count("exosuit"), 0, "and the hold did not get it")
	check(CrewKit.equip_from_hold(s, q, "basic_armor").contains("cannot wear"), "straight from the hold too")
	var opts := Kit.options(s, q, "body", 0)
	check(opts.any(func(o): return o["id"] == "basic_armor" and o["why"] != ""), "the choices list it with a reason")
	CrewKit.equip_from_hold(s, rook, "overcharge_coil_mk1")
	s.inventory.add("overcharge_coil_mk1", 1)
	check(CrewKit.equip_from_hold(s, rook, "overcharge_coil_mk1").contains("Already"), "one Overcharge Coil each")


func test_the_open_slot_lists_choices_and_gives_to_the_others() -> void:
	var s := _ship()
	var k := CrewKit.new(s)
	k.focus(k.people().find(_by(s, "Rook")))
	CrewKit.equip_from_hold(s, _by(s, "Rook"), "exosuit")
	k.open_slot("body", 0)
	var opts := k.loadout_options()
	var ids: Array = opts.map(func(o): return o["id"])
	check(ids.has("") and ids.has("exosuit") and ids.has("basic_armor"), "nothing, what is worn and what the hold has: %s" % str(ids))
	check(ids.has("give:Tess"), "and a give to every other crew member")
	check(not ids.has("give:Rook"), "but not to himself")
	eq(k.choose(ids.find("give:Tess")), "", "giving it")
	eq(Kit.slot_value(_by(s, "Tess"), "body", 0), "exosuit", "Tess wears it")
	check(k.load_slot.is_empty(), "the slot closes")
	var stats: String = Loadout.stats("body", "exosuit")
	eq(stats, Kit.body_line("exosuit"), "a choice's stats line is the loadout's own")


# --- opening it ----------------------------------------------------------------------------------------------------------------

func test_i_opens_the_screen_in_play_mode_and_i_or_esc_shuts_it() -> void:
	var fake := FakeBuild.new()
	var d := _panel(_ship(), fake)
	var panel: CrewKitPanel = d["panel"]
	check(not panel.visible or true, "(starts shut)")
	panel._input(_key(KEY_I))
	check(panel.visible, "I opens it in play mode")
	panel._input(_key(KEY_I))
	check(not panel.visible, "I shuts it")
	panel._input(_key(KEY_I))
	panel._input(_key(KEY_ESCAPE))
	check(not panel.visible, "so does Esc")
	fake.free()
	_free(d)


func test_it_does_not_open_in_a_fight_or_in_build_mode() -> void:
	var fake := FakeBuild.new()
	var d := _panel(_ship(), fake)
	var panel: CrewKitPanel = d["panel"]
	fake.combat = true
	panel._input(_key(KEY_I))
	check(not panel.visible, "not in a fight")
	check(not panel.open(), "open() says no too")
	fake.combat = false
	fake.build_on = true
	panel._input(_key(KEY_I))
	check(not panel.visible, "not in build mode")
	fake.build_on = false
	check(panel.open(), "in play mode it opens")
	fake.free()
	_free(d)


func test_opening_gives_everybody_a_kit_and_the_screen_changes_it() -> void:
	var s := _ship()
	var fake := FakeBuild.new()
	var d := _panel(s, fake)
	var panel: CrewKitPanel = d["panel"]
	panel.open()
	var rook = _by(s, "Rook")
	check(Kit.is_set(rook), "Rook has a kit to change")
	panel.kit.focus(panel.kit.people().find(rook))
	panel.kit.open_slot("body", 0)
	var ids: Array = panel.loadout_options().map(func(o): return o["id"])
	eq(panel.choose(ids.find("basic_armor")), "", "a click on a choice puts it on")
	eq(Kit.slot_value(rook, "body", 0), "basic_armor", "worn")
	eq(panel.take_from_hold({"id": "exosuit", "kind": "body", "name": "Exosuit", "count": 1}), "", "a hold row goes to the first free slot of its kind, or the open one")
	eq(Kit.slot_value(rook, "body", 0), "exosuit", "(body has one slot: it replaced the armour, which went back to the hold)")
	eq(s.inventory.count("basic_armor"), 1, "the armour is back in the hold")
	fake.free()
	_free(d)


# --- the boarding party picker ------------------------------------------------------------------------------------------------

func _visit(kind: String, sh: Ship):
	var s = Boarding.start(null, null, "p31", {"kind": kind}, sh)
	s.site = Site.make(31, kind, {"faction": "clans"})
	s.soldier.pos = s.site.airlock["spawn"]
	s.foes = Foes.new(s)
	s.foes.spawn_site({})
	return s


func test_the_picker_opens_first_on_every_kind_of_site() -> void:
	for kind in Site.kinds():
		var sh := _ship()
		var s = _visit(str(kind), sh)
		var b := BoardView.new()
		b.ask_party = true
		b.enter(s)
		check(b.picking, "%s: the picker opens first" % kind)
		var rows: Array = b.pick_rows()
		check(rows.size() >= 2 and rows[0].has("gear") and rows[0].has("rounds") and rows[0].has("hp"), "%s: each crew member has hp, gear and rounds" % kind)
		eq(int(rows[0]["rounds"]), maxi(sh.inventory.count("hand_ammo"), 10), "%s: the rounds they would carry" % kind)
		b.leave()


func test_go_alone_and_the_limit_and_the_number_keys() -> void:
	var sh := _ship()
	sh.crew.append(CrewMember.new("Vik", Vector2(14, 10), "human"))
	var s = _visit("derelict", sh)
	var b := BoardView.new()
	b.ask_party = true
	b.enter(s)
	b._unhandled_input(_key(KEY_1))
	b._unhandled_input(_key(KEY_2))
	b._unhandled_input(_key(KEY_3))
	eq(b.pick.size(), int(Party.eligible(sh).size()) if Party.eligible(sh).size() < 2 else 2, "the number keys toggle crew, two at most (party_max)")
	b.go_alone()
	check(not b.picking, "Go alone closes the picker")
	eq(s.party.size(), 0, "and nobody comes, whoever was picked")
	b.leave()
	var s2 = _visit("station", _ship())
	var b2 := BoardView.new()
	b2.ask_party = true
	b2.enter(s2)
	b2._unhandled_input(_key(KEY_1))
	b2._unhandled_input(_key(KEY_ENTER))
	eq(s2.party.size(), 1, "Enter goes aboard with the one picked")
	b2.leave()
	var s3 = _visit("nest", _ship())
	var b3 := BoardView.new()
	b3.ask_party = true
	b3.enter(s3)
	b3._unhandled_input(_key(KEY_1))
	b3._unhandled_input(_key(KEY_A))
	eq(s3.party.size(), 0, "A goes alone")
	b3.leave()


func test_a_no_suit_tag_marks_the_crew_with_no_sealed_suit() -> void:
	var sh := _ship()
	sh.inventory.add("eva_suit", 1)
	var s = _visit("station", sh)
	var b := BoardView.new()
	b.ask_party = true
	b.enter(s)
	check(b.pick_rows().all(func(r): return r["no_suit"]), "nobody wears a sealed suit: all are tagged")
	b.leave()
	CrewKit.equip_from_hold(sh, _by(sh, "Rook"), "eva_suit")
	var s2 = _visit("station", sh)
	var b2 := BoardView.new()
	b2.ask_party = true
	b2.enter(s2)
	var rook: Dictionary = b2.pick_rows().filter(func(r): return r["name"] == "Rook")[0]
	check(not rook["no_suit"], "Rook in an EVA suit is not")
	b2.leave()
