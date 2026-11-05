extends "res://tests/base_test.gd"
## Crafting in the game: the ship owns a Crafting (saved), ShipSim ticks it at the level of the ship's
## best powered fabricator and logs what happens, and the panel (C) queues and cancels jobs.

const CombatView = preload("res://scripts/combat/combat_view.gd")
const CraftingPanel = preload("res://scripts/ui/crafting_panel.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")

const KICKJET := "engine_scrap_mk1"  ## 16 scrap, level 1, 20 s


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A reactor (x 10..13) and a fabricator (x 15..18, y 10..11) on one cable in the test room, a stock of scrap and 40 copper.
func _rig() -> Dictionary:
	var ship := Fixture.room_ship()
	var d := {"ship": ship}
	d["reactor"] = Fixture.put(ship, "reactor_mk1", 10, 10)
	d["fab"] = Fixture.put(ship, "fabricator", 15, 10)
	Fixture.wire(ship, [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	return d


func _sim(ship: Ship) -> ShipSim:
	var sim := ShipSim.new()
	sim.ships = [ship]
	return sim


func _run(sim: ShipSim, seconds: float, step := 0.5) -> void:
	for i in roundi(seconds / step):
		sim.step(step)


func _texts(ship: Ship) -> Array:
	return ship.events.map(func(e): return e["text"])


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


# --- the ship and the sim -------------------------------------------------------------------------------

func test_a_ship_owns_its_crafting_and_the_best_fabricator_counts() -> void:
	var d := _rig()
	var ship: Ship = d["ship"]
	check(ship.crafting.is_known(KICKJET) and not ship.crafting.is_known("reactor_mk2"), "the start blueprints")
	var fab := Workshop.best(ship)
	eq([fab["level"], fab["uid"], fab["count"], fab["tools"]], [1, d["fab"], 1, []], "a lone powered fabricator is level 1")
	eq(Fixture.put(ship, "fabricator", 15, 12), -1, "a second fabricator is refused: one per ship")
	var arm := Fixture.put(ship, "robot_arm", 19, 10)
	Fixture.wire(ship, [Vector2i(18, 11), Vector2i(19, 11)])
	ship.refresh()
	fab = Workshop.best(ship)
	eq([fab["level"], fab["modules"], fab["speed"]], [1, [arm], 1.25], "a powered Robot Arm in the room: crafting 25% faster, the level is the fabricator's own")
	ship.components.instances[d["fab"]]["fab_level"] = 2
	eq(Workshop.best(ship)["level"], 2, "an upgrade makes it level 2")
	ship.cables.cells.clear()
	ship.mark_dirty()
	fab = Workshop.best(ship)
	eq([fab["level"], fab["uid"], fab["count"]], [0, -1, 1], "no power: level 0, none usable")
	eq(Workshop.best(Fixture.room_ship())["count"], 0, "a ship without one")


func test_the_sim_crafts_into_the_cargo_and_the_chronicle_says_so() -> void:
	var d := _rig()
	var ship: Ship = d["ship"]
	var sim := _sim(ship)
	var scrap := ship.inventory.count("scrap")
	eq(ship.crafting.enqueue(KICKJET, ship.inventory, Workshop.best(ship)), "", "queued")
	eq(ship.inventory.count("scrap"), scrap - 16, "the materials are paid up front")
	_run(sim, 19.5)
	eq(ship.inventory.count(KICKJET), 0, "not done after 19.5 s")
	near(ship.crafting.queue[0]["progress"], 19.5, "the job has progress", 0.01)
	_run(sim, 1.0)
	eq(ship.inventory.count(KICKJET), 1, "a Kickjet in the cargo after 20 s")
	check(ship.crafting.queue.is_empty(), "the queue is empty")
	check(_texts(ship).has("Crafted Kickjet"), "Crafted Kickjet: %s" % [_texts(ship)])
	sim.free()


func test_an_unpowered_fabricator_pauses_and_resumes_the_queue() -> void:
	var d := _rig()
	var ship: Ship = d["ship"]
	var sim := _sim(ship)
	ship.crafting.enqueue(KICKJET, ship.inventory, Workshop.best(ship))
	_run(sim, 5.0)
	near(ship.crafting.queue[0]["progress"], 5.0, "5 s done", 0.01)
	var cables: Dictionary = ship.cables.cells.duplicate()
	ship.cables.cells.clear()
	ship.mark_dirty()
	_run(sim, 5.0)
	near(ship.crafting.queue[0]["progress"], 5.0, "nothing moves without power", 0.01)
	check(ship.crafting.paused, "paused")
	eq(_texts(ship).count("Fabricator offline: crafting paused"), 1, "the chronicle says so once")
	ship.cables.cells = cables
	ship.mark_dirty()
	_run(sim, 5.0)
	near(ship.crafting.queue[0]["progress"], 10.0, "and it carries on when the power is back", 0.01)
	check(not ship.crafting.paused and _texts(ship).has("Fabricator online: crafting resumed"), "resumed and logged")
	sim.free()


func test_a_job_too_big_for_the_fabricator_says_so() -> void:
	var d := _rig()
	var ship: Ship = d["ship"]
	var sim := _sim(ship)
	ship.crafting.unlock("engine_mk2")  # level 2
	ship.inventory.add("titanium", 8)
	ship.crafting.enqueue("engine_mk2", ship.inventory, {"level": 2, "tools": []})  # queued while an arm was there
	_run(sim, 1.0)
	check(ship.crafting.paused, "level 1 cannot run it")
	check(_texts(ship).has("Fabricator too weak for Concord Thruster Mk2: crafting paused"), "named in the chronicle: %s" % [_texts(ship)])
	sim.free()


func test_the_save_keeps_the_queue_and_the_blueprints() -> void:
	var d := _rig()
	var ship: Ship = d["ship"]
	var sim := _sim(ship)
	var scrap := ship.inventory.count("scrap")
	ship.crafting.unlock("pulse_mk1")
	ship.crafting.enqueue(KICKJET, ship.inventory, Workshop.best(ship))
	ship.crafting.enqueue("radiator", ship.inventory, Workshop.best(ship))
	_run(sim, 5.0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))
	var b := Ship.new_starter()
	eq(b.load_dict(saved), "", "loads")
	eq(b.crafting.queue.map(func(j): return j["recipe"]), [KICKJET, "radiator"], "the queue is back")
	near(b.crafting.queue[0]["progress"], 5.0, "with its progress", 0.01)
	eq(b.crafting.queue[0]["paid"], {"scrap": 16}, "and what was paid")
	check(b.crafting.is_known("pulse_mk1"), "the unlocked blueprint is known")
	eq(b.inventory.count("scrap"), scrap - 16 - 10, "the cargo kept the spent materials")
	eq(JSON.stringify(b.to_dict()), JSON.stringify(ship.to_dict()), "and it saves back the same")
	var bad: Dictionary = saved.duplicate(true)
	bad["crafting"]["queue"][0]["recipe"] = "no_such_recipe"
	var c := Ship.new_starter()
	c.name = "untouched"
	eq(c.load_dict(bad), "bad job in the queue", "a broken queue is refused")
	eq([c.name, c.crafting.queue.size(), c.components.instances.size()], ["untouched", 0, 0], "and nothing was replaced")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ships/starter_courier.json"))
	raw.erase("crafting")  # the design files carry the blueprints they were made with; this is a design without the section
	var design := Ship.new_starter()
	eq(design.load_dict(raw), "", "a design file without the section loads")
	eq([design.crafting.queue.size(), design.crafting.known.size()], [0, Ship.new_starter().crafting.known.size()], "and starts with the start blueprints")
	sim.free()


# --- the panel --------------------------------------------------------------------------------------------

func _panel(ship: Ship) -> Dictionary:
	var sim := _sim(ship)
	var panel := CraftingPanel.new()
	panel.sim = sim
	panel.size = Vector2(1600.0, 900.0)
	return {"panel": panel, "sim": sim}


func _free(d: Dictionary) -> void:
	d["panel"].free()
	d["sim"].free()


func test_the_panel_lists_every_recipe_by_category_known_ones_first() -> void:
	var d := _panel(_rig()["ship"])
	var panel: CraftingPanel = d["panel"]
	var rows := panel.rows()
	eq(rows[0], {"header": "Systems"}, "systems first")
	var headers := rows.filter(func(r): return r.has("header")).map(func(r): return r["header"])
	eq(headers, ["Systems", "Gear", "Materials", "Modules"], "the four categories in order")
	var ids := panel.recipe_ids()
	check(ids.has(KICKJET) and ids.has("pistol") and ids.has("polymer") and ids.has("robot_arm"), "known recipes of each kind")
	check(not ids.has("reactor_mk2") and not ids.has("laser_mk2"), "recipes whose blueprint is unknown are hidden")
	for id in ids:
		check(panel.sim.player_ship().crafting.is_known(id), "%s is listed only because it is known" % id)
	eq(panel.reason(KICKJET), "", "Kickjet can be made")
	panel.sim.player_ship().crafting.unlock("reactor_mk2")
	check(panel.recipe_ids().has("reactor_mk2"), "learning it lists it")
	eq(panel.reason("reactor_mk2"), "needs fabricator level 3", "level 3 is out of reach")
	panel.sim.player_ship().crafting.unlock("laser_mk2")
	eq(panel.reason("laser_mk2"), "needs fabricator level 2", "and laser_mk2 needs level 2 first")
	panel.sim.player_ship().inventory.counts.clear()
	check(panel.reason("reactor_scrap_mk1").begins_with("missing: 30 scrap"), "missing materials are named: " + panel.reason("reactor_scrap_mk1"))
	_free(d)


func test_unknown_recipes_are_hidden_and_racial_tech_waits_for_its_blueprint() -> void:
	var d := _panel(_rig()["ship"])
	var panel: CraftingPanel = d["panel"]
	var ship: Ship = panel.sim.player_ship()
	var ids := panel.recipe_ids()
	check(not ids.has("reactor_mk2") and not ship.crafting.is_known("reactor_mk2"), "an unknown recipe of the game's own tech is not listed")
	check(not ids.has("basalt_vacuum_forge"), "nor is racial tech of a people not met")
	panel.selected = "reactor_mk2"
	panel.craft_selected()
	eq(panel.message, "Reactor Mk2: " + CraftingPanel.BLUEPRINT_HELP, "asking for it explains where blueprints come from")
	eq(ship.crafting.queue.size(), 0, "and queues nothing")
	ship.crafting.unlock("basalt_vacuum_forge")
	check(panel.recipe_ids().has("basalt_vacuum_forge"), "learning the blueprint lists it")
	_free(d)


func test_the_selected_recipe_is_described_and_the_help_box_toggles() -> void:
	var d := _panel(_rig()["ship"])
	var panel: CraftingPanel = d["panel"]
	panel.open()
	panel.selected = KICKJET
	var desc := panel.described()
	check(desc["what"].begins_with("Pushes and steers") and desc["lore"] != "", "what the part does, and its lore: " + str(desc["what"]))
	check(desc["stats"].any(func(r): return r[0] == "Thrust"), "its stats")
	panel.selected = "pistol"
	check(panel.described()["what"].contains("gear"), "gear gets its line too")
	check(not panel.help_open, "the help box starts shut")
	panel._input(_key(KEY_SLASH))
	check(panel.help_open, "? opens it")
	check(panel.help_lines().size() >= 4 and panel.help_lines()[0].contains("recipe"), "it explains the recipe, the stations, the hold and blueprints")
	panel._gui_input(_click(panel.help_rect().get_center()))
	check(not panel.help_open, "a click on the ? button shuts it")
	_free(d)


func test_the_panel_enqueues_and_cancels() -> void:
	var rig := _rig()
	var ship: Ship = rig["ship"]
	var d := _panel(ship)
	var panel: CraftingPanel = d["panel"]
	panel.open()
	var scrap := ship.inventory.count("scrap")
	eq(panel.selected, panel.recipe_ids()[0], "the cursor starts on the first recipe")
	eq(panel.craft(KICKJET), "", "queued")
	eq([ship.crafting.queue.size(), ship.inventory.count("scrap"), panel.message], [1, scrap - 16, "Queued Kickjet"], "the job, the cost and the message")
	check(panel.cancel_job(0), "cancelled")
	eq([ship.crafting.queue.size(), ship.inventory.count("scrap")], [0, scrap], "the materials came back")
	check(not panel.cancel_job(0), "no job to cancel")
	eq(panel.craft("reactor_mk2"), "blueprint not known", "an unknown blueprint")
	check(panel.message_bad, "and it is shown as a refusal")
	for i in 8:
		panel.craft("bed")
	eq(panel.craft("bed"), "queue full", "eight jobs at most")
	_free(d)


func test_the_panel_keys() -> void:
	var rig := _rig()
	var ship: Ship = rig["ship"]
	var d := _panel(ship)
	var panel: CraftingPanel = d["panel"]
	panel.visible = false  # as the scene leaves it
	panel._input(_key(KEY_C))
	check(panel.visible, "C opens it")
	var first: String = panel.selected
	panel._input(_key(KEY_RIGHT))
	eq(panel.selected, panel.recipe_ids()[1], "Right moves the cursor one card")
	panel._input(_key(KEY_LEFT))
	eq(panel.selected, first, "Left moves it back")
	panel._input(_key(KEY_DOWN))
	check(panel.selected != first and panel.recipe_ids().find(panel.selected) >= 1, "Down moves the cursor a line of cards")
	panel._input(_key(KEY_UP))
	panel._input(_key(KEY_UP))
	eq(panel.selected, first, "Up goes back and stops at the top")
	panel._input(_key(KEY_ENTER))
	eq(ship.crafting.queue.size(), 1, "Enter queues the selected recipe")
	var known := ship.crafting.known.size()
	panel._input(_key(KEY_U))
	eq(ship.crafting.known.size(), known + 1, "U unlocks a blueprint")
	check(panel.message.begins_with("Unlocked blueprint: "), panel.message)
	panel._input(_key(KEY_ESCAPE))
	check(not panel.visible, "Esc closes it")
	panel._input(_key(KEY_C))
	panel._input(_key(KEY_C))
	check(not panel.visible, "C toggles")
	panel._input(_key(KEY_ENTER))
	eq(ship.crafting.queue.size(), 1, "keys do nothing while it is shut")
	panel.open()
	panel.move(1000)
	eq(panel.selected, panel.recipe_ids()[panel.recipe_ids().size() - 1], "the cursor stops at the last recipe")
	check(panel.row_rect(panel.rows().size() - 1).size != Vector2.ZERO, "and the list scrolled to show it")
	_free(d)


func test_the_panel_clicks() -> void:
	var rig := _rig()
	var ship: Ship = rig["ship"]
	var d := _panel(ship)
	var panel: CraftingPanel = d["panel"]
	panel.open()
	var row := 1  # the first recipe, under the "Systems" header
	var at: Vector2 = panel.row_rect(row).get_center()
	eq(panel.row_at(at), row, "the row under the mouse")
	panel._gui_input(_click(at))
	eq(ship.crafting.queue.size(), 0, "a click on a recipe only selects it")
	eq(panel.selected, panel.rows()[row]["id"], "the one clicked")
	var dbl := _click(at)
	dbl.double_click = true
	panel._gui_input(dbl)
	eq(ship.crafting.queue.size(), 1, "a double-click queues it")
	eq(ship.crafting.queue[0]["recipe"], panel.rows()[row]["id"], "the one clicked")
	panel._gui_input(_click(panel.row_rect(0).get_center()))
	eq(ship.crafting.queue.size(), 1, "a header does nothing")
	panel._gui_input(_click(panel.queue_rect_btn().get_center()))
	eq(ship.crafting.queue.size(), 2, "the Queue button queues the selected recipe")
	var job: Vector2 = panel.job_rect(0).get_center()
	eq(panel.job_at(job), 0, "the job under the mouse")
	panel._gui_input(_click(job))
	panel._gui_input(_click(job))
	eq(ship.crafting.queue.size(), 0, "a click on a job cancels it")
	_free(d)


func test_the_debug_unlock_is_random_but_repeatable() -> void:
	var picks := []
	for run in 2:
		var d := _panel(_rig()["ship"])
		var panel: CraftingPanel = d["panel"]
		eq(panel.debug_unlock(), "", "unlocked")
		picks.append(panel.selected)
		check(not Ship.new("x").crafting.is_known(panel.selected), "it was a locked one")
		var left: int = panel.sim.player_ship().crafting.ids().size() - panel.sim.player_ship().crafting.known.size()
		for i in left:
			panel.debug_unlock()
		eq(panel.debug_unlock(), "none locked", "none left in the end")
		_free(d)
	eq(picks[0], picks[1], "the same ship draws the same blueprint")


func test_the_debug_mods_key_puts_the_nine_boarding_mods_in_the_hold() -> void:
	var d := _panel(_rig()["ship"])
	var panel: CraftingPanel = d["panel"]
	eq(panel.debug_mods(), "", "done")
	var ship: Ship = panel.sim.player_ship()
	for id in ["spotter_cam", "salvage_rig", "overcharge_coil"]:
		for tier in [1, 2, 3]:
			eq(ship.inventory.count("%s_mk%d" % [id, tier]), 1, "%s Mk %d" % [id, tier])
	_free(d)


func test_the_debug_keys_are_gated_by_the_build() -> void:
	var d := _panel(_rig()["ship"])
	var panel: CraftingPanel = d["panel"]
	check(panel.debug_keys == OS.is_debug_build(), "the keys follow the build (a release export has none)")
	panel.visible = true
	panel.debug_keys = false  # as in a release export
	var ship: Ship = panel.sim.player_ship()
	var known: int = ship.crafting.known.size()
	panel._input(_key(KEY_U))
	panel._input(_key(KEY_M))
	eq(ship.crafting.known.size(), known, "U learns nothing in a release build")
	eq(ship.inventory.count("spotter_cam_mk1"), 0, "M puts no mods in the hold in a release build")
	panel.debug_keys = true
	panel._input(_key(KEY_U))
	panel._input(_key(KEY_M))
	eq(ship.crafting.known.size(), known + 1, "U learns a blueprint in a debug build")
	eq(ship.inventory.count("spotter_cam_mk1"), 1, "M gives the mods in a debug build")
	_free(d)


func test_the_panel_stays_shut_in_a_fight() -> void:
	var main := Node.new()
	var combat := CombatView.new()
	combat.name = "Combat"
	main.add_child(combat)
	var layer := Node.new()
	main.add_child(layer)
	var panel := CraftingPanel.new()
	layer.add_child(panel)
	panel.visible = false
	panel._input(_key(KEY_C))
	check(panel.visible, "it opens when no fight is on")
	panel.visible = false
	combat.active = true
	panel._input(_key(KEY_C))
	check(not panel.visible, "and not during one")
	main.free()
