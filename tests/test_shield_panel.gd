extends "res://tests/base_test.gd"
## The Shields tab (H): the +/- of every sector and the presets, the two custom slots, what it shows for
## one piece, two, four and eight sectors, its keys and clicks, and the hook that opens it in build mode.

const BuildMode = preload("res://scripts/build/build_mode.gd")
const Balance = preload("res://scripts/combat/shield_balance.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const ShieldPanel = preload("res://scripts/ui/shield_panel.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _click(p: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	return e


## A walled room with a reactor and the shield generator `gen` wired to it ("" for none), in a panel's sim.
## `sectors` patches the generator's sector count (0: leave the data's).
func _rig(gen: String, sectors := 0) -> Dictionary:
	var ship := Fixture.room_ship()
	if sectors > 0 and gen != "":
		ship.components.by_id[gen]["stats"]["sectors"] = sectors
	Fixture.put(ship, "reactor_mk1", 10, 10)
	if gen != "":
		Fixture.put(ship, gen, 15, 10)
		Fixture.wire(ship, [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	var sim := ShipSim.new()
	sim.ships = [ship]
	var panel := ShieldPanel.new()
	panel.sim = sim
	panel.size = Vector2(1600.0, 900.0)
	return {"ship": ship, "sim": sim, "panel": panel}


func _free(d: Dictionary) -> void:
	d["panel"].free()
	d["sim"].free()


func test_the_panel_reads_the_generator() -> void:
	var d := _rig("shield_mk2")
	var panel: ShieldPanel = d["panel"]
	eq([panel.sector_count(), panel.layers()], [2, 2], "a Mk2: two sectors, two layers")
	eq(panel.weights(), [1.0, 1.0], "even to begin with")
	eq(panel.caps(), [2.0, 2.0], "so two layers each")
	eq(panel.generators(), ["Shield Mk2"], "the generator is named")
	_free(d)
	d = _rig("shield_neon_mk1")
	eq([d["panel"].sector_count(), d["panel"].layers()], [4, 2], "the Neon Lattice: four sectors")
	_free(d)
	d = _rig("shield_mk1")
	eq([d["panel"].sector_count(), d["panel"].layers()], [1, 1], "a Mk1: one piece")
	_free(d)
	d = _rig("")
	eq([d["panel"].sector_count(), d["panel"].layers(), d["panel"].generators()], [1, 0, []], "no generator: nothing")
	_free(d)
	d = _rig("shield_mk2")
	d["ship"].components.instances[d["ship"].components.instances.keys().back()]["status"] = "disabled"
	check(d["panel"].generators().is_empty(), "a disabled generator is not counted")
	_free(d)


func test_plus_and_minus_move_the_weights_and_keep_them_summed() -> void:
	var d := _rig("shield_neon_mk1")
	var panel: ShieldPanel = d["panel"]
	var ship: Ship = d["ship"]
	eq(panel.adjust(0, 1), "", "+ on the bow")
	eq(panel.weights(), [1.5, 1.0, 0.5, 1.0], "half a weight from the stern")
	eq(ship.shield_balance["weights"], [1.5, 1.0, 0.5, 1.0], "kept on the ship")
	eq(panel.message, "Bow 1.5", "and said")
	panel.adjust(0, 1)
	eq(panel.adjust(0, 1), "Bow is at the most (2)", "+ past 2 is refused")
	check(panel.message_bad, "as a refusal")
	eq(panel.weights(), [2.0, 1.0, 0.0, 1.0], "nothing changed")
	eq(panel.adjust(2, -1), "Stern is already at 0", "- past 0 is refused")
	eq(panel.adjust(0, -1), "", "- on the bow")
	eq(panel.weights(), [1.5, 1.0, 0.5, 1.0], "gives half a weight to the stern")
	for i in 30:
		panel.adjust(i % 4, 1 if i % 3 != 0 else -1)
		check(Balance.valid(panel.weights(), 4), "press %d: still valid and summed: %s" % [i, str(panel.weights())])
	panel.apply_preset("Even")
	eq(ship.shield_balance["weights"], [], "even is kept as nothing chosen")
	_free(d)


func test_the_presets() -> void:
	var d := _rig("shield_neon_mk1")
	var panel: ShieldPanel = d["panel"]
	var want := {"Even": [1.0, 1.0, 1.0, 1.0], "Bow": [2.0, 1.0, 0.0, 1.0], "Stern": [0.0, 1.0, 2.0, 1.0], "Port": [1.0, 0.0, 1.0, 2.0], "Starboard": [1.0, 2.0, 1.0, 0.0]}
	for name in Balance.PRESETS:
		eq(panel.apply_preset(name), "", name + " applies")
		eq(panel.weights(), want[name], name + " sets the weights")
	_free(d)
	d = _rig("shield_mk2")
	panel = d["panel"]
	eq(panel.apply_preset("Bow"), "", "two sectors: bow")
	eq(panel.weights(), [2.0, 0.0], "double bow")
	eq(panel.apply_preset("Port"), "Port needs 4 sectors", "no port with two sectors")
	check(not panel.button("preset:Port")["enabled"] and not panel.button("preset:Starboard")["enabled"], "and those buttons are greyed")
	check(panel.button("preset:Bow")["enabled"], "bow is not")
	eq(panel.weights(), [2.0, 0.0], "a refusal leaves the weights")
	_free(d)


func test_the_custom_slots_save_and_load() -> void:
	var d := _rig("shield_neon_mk1")
	var panel: ShieldPanel = d["panel"]
	var ship: Ship = d["ship"]
	eq(panel.load_slot(0), "Slot 1 is empty", "nothing saved yet")
	panel.apply_preset("Bow")
	eq(panel.save_slot(0), "", "save the double bow in slot 1")
	panel.apply_preset("Port")
	eq(panel.save_slot(1), "", "and the port heavy one in slot 2")
	eq(ship.shield_balance["presets"], [[2.0, 1.0, 0.0, 1.0], [1.0, 0.0, 1.0, 2.0]], "both are on the ship")
	panel.apply_preset("Even")
	eq(panel.load_slot(0), "", "load slot 1")
	eq(panel.weights(), [2.0, 1.0, 0.0, 1.0], "the bow one is back")
	eq(panel.load_slot(1), "", "load slot 2")
	eq(panel.weights(), [1.0, 0.0, 1.0, 2.0], "the port one")
	eq(panel.save_slot(2), "no such slot", "there are only two")
	ship.shield_balance["presets"][0] = [2.0, 0.0]
	eq(panel.load_slot(0), "Slot 1 was saved for 2 sectors; this bubble has 4", "a slot kept for another count is refused")
	eq(panel.weights(), [1.0, 0.0, 1.0, 2.0], "and changes nothing")
	var saved: Variant = JSON.parse_string(JSON.stringify(ship.to_dict()))
	var back := Ship.new("b", Fixture.room_ship().grid)
	eq(back.load_dict(saved), "", "the ship saves")
	eq(back.shield_balance, ship.shield_balance, "slots and weights come back")
	_free(d)


func test_one_piece_has_nothing_to_set() -> void:
	var d := _rig("shield_mk1")
	var panel: ShieldPanel = d["panel"]
	eq(panel.buttons(), [], "no buttons")
	for r in [panel.adjust(0, 1), panel.apply_preset("Bow"), panel.save_slot(0), panel.load_slot(0)]:
		eq(r, "This generator is one piece: no balance to set.", "every action says so")
	eq(panel.weights(), [1.0], "one weight")
	eq(d["ship"].shield_balance, Balance.fresh(), "and nothing is kept")
	_free(d)


func test_every_button_is_on_screen_and_clear_of_the_others() -> void:
	for gen in [["shield_mk2", 0], ["shield_neon_mk1", 0], ["shield_mk1", 8]]:
		var d := _rig(gen[0], gen[1])
		var panel: ShieldPanel = d["panel"]
		var n := panel.sector_count()
		var list := panel.buttons()
		var cells := 2 * n + Balance.PRESETS.size() + 2 * Balance.SLOTS
		eq(list.size(), cells if n > 1 else 0, "%d sectors: %d buttons" % [n, cells])
		var screen := Rect2(Vector2.ZERO, panel.size)
		for i in list.size():
			var r: Rect2 = list[i]["rect"]
			check(screen.encloses(r), "%d sectors: %s is on screen (%s)" % [n, list[i]["id"], str(r)])
			for j in range(i + 1, list.size()):
				check(not r.intersects(list[j]["rect"]), "%d sectors: %s and %s do not overlap" % [n, list[i]["id"], list[j]["id"]])
		_free(d)
	# the bubble has a place on the screen for each sector, and the map fits its rect
	var e := _rig("shield_neon_mk1")
	var p: ShieldPanel = e["panel"]
	var s: Dictionary = p.map_transform()
	check(s["s"] > 4.0, "the ship is drawn at a size you can read: %f px a cell" % s["s"])
	check(p.map_rect().encloses(Rect2(p.to_screen(p.map_bounds().position), p.map_bounds().size * float(s["s"]))), "the map's cells fit its rect")
	_free(e)


func test_the_panel_keys_and_clicks() -> void:
	var d := _rig("shield_neon_mk1")
	var panel: ShieldPanel = d["panel"]
	panel.visible = false
	panel._input(_key(KEY_ESCAPE))
	check(not panel.visible, "shut: keys do nothing")
	panel.open()
	check(panel.visible, "open")
	panel._input(_key(KEY_ESCAPE))
	check(not panel.visible, "Esc closes it")
	panel.open()
	panel._input(_key(KEY_H))
	check(not panel.visible, "H closes it")
	panel.open()
	var plus: Rect2 = panel.button("plus:1")["rect"]
	panel._gui_input(_click(plus.get_center()))
	eq(panel.weights(), [1.0, 1.5, 1.0, 0.5], "a click on a sector's + gives it half a weight (the opposite port loses it)")
	panel._gui_input(_click(panel.button("minus:1")["rect"].get_center()))
	eq(panel.weights(), [1.0, 1.0, 1.0, 1.0], "and its - takes it back")
	panel._gui_input(_click(panel.button("preset:Stern")["rect"].get_center()))
	eq(panel.weights(), [0.0, 1.0, 2.0, 1.0], "a click on a preset")
	panel._gui_input(_click(panel.button("save:0")["rect"].get_center()))
	panel._gui_input(_click(panel.button("preset:Even")["rect"].get_center()))
	panel._gui_input(_click(panel.button("load:0")["rect"].get_center()))
	eq(panel.weights(), [0.0, 1.0, 2.0, 1.0], "Save and Load of slot 1")
	eq(panel.button_at(Vector2(5.0, 5.0)), "", "a click elsewhere hits nothing")
	var weights := panel.weights()
	panel._gui_input(_click(Vector2(5.0, 5.0)))
	eq(panel.weights(), weights, "and does nothing")
	eq(panel.press("nonsense"), "no such button", "an unknown button")
	_free(d)


func test_h_opens_the_tab_in_build_and_play_mode_but_not_in_a_fight() -> void:
	var d := _rig("shield_mk2")
	var b := BuildMode.new()
	b.sim = d["sim"]
	b.shields = d["panel"]
	var h := _key(KEY_H)
	b.build_on = true
	b._on_key(h)
	check(d["panel"].visible, "H in build mode opens it")
	d["panel"].close()
	b.build_on = false
	b._on_key(h)
	check(d["panel"].visible, "and in play mode")
	d["panel"].close()
	b.combat = true
	b._unhandled_input(h)
	check(not d["panel"].visible, "but not during a fight (build mode ignores every key then)")
	b.free()
	_free(d)
