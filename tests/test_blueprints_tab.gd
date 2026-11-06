extends "res://tests/base_test.gd"
## The craft panel's Fabricator tab (every blueprint you know, grouped, NEW tags saved with the run; it was the Blueprints tab before the merge), the way to a smelter (the no-smelter hint, the
## Ledger's Slag Pot goal), the line that says a blueprint was learned, and the hover card with its separate Queue action.

const Advisor = preload("res://scripts/sim/advisor.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const CraftingPanel = preload("res://scripts/ui/crafting_panel.gd")
const Crafting = preload("res://scripts/craft/crafting.gd")
const PartCard = preload("res://scripts/ui/part_card.gd")
const PicCard = preload("res://scripts/ui/pic_card.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")


func _panel(ship: Ship) -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [ship]
	var panel := CraftingPanel.new()
	panel.sim = sim
	panel.size = Vector2(1600.0, 900.0)
	return {"panel": panel, "sim": sim}


func _free(d: Dictionary) -> void:
	d["panel"].free()
	d["sim"].free()


func _click(p: Vector2, double := false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	e.double_click = double
	return e


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _row_of(panel: CraftingPanel, id: String) -> int:
	var all := panel.rows()
	for i in all.size():
		if all[i].get("id", "") == id:
			return i
	return -1


func test_the_fabricator_tab_lists_every_known_blueprint_grouped() -> void:
	var ship := Fixture.room_ship()
	var d := _panel(ship)
	var panel: CraftingPanel = d["panel"]
	panel.open()
	eq(panel.station, "fabricator", "the one tab for them")
	check(not panel.set_station("blueprints"), "the Blueprints tab is gone")
	var ids := panel.recipe_ids()
	var known: Array = ship.crafting.known.keys().filter(func(id): return ship.crafting.station_of(id) == "fabricator")
	eq(ids.size(), known.size(), "one row for each fabricator blueprint known (the smelter's are on its tab)")
	for id in known:
		check(ids.has(id), "%s is listed" % id)
	var heads := panel.rows().filter(func(r): return r.has("header")).map(func(r): return r["header"])
	check(heads.has("Smelters") and heads.has("Materials") and heads.has("Weapons"), "grouped: " + str(heads))
	var seen := {}
	for id in ids:
		check(not seen.has(id), id + " once")
		seen[id] = true
	check(heads.find("Weapons") < heads.find("Smelters") and heads.find("Smelters") < heads.find("Materials"), "families first, then materials")
	check(heads.has(CraftingPanel.G_GEAR) and heads.has(CraftingPanel.G_ITEMS), "hand gear and items have their groups")
	var rows := panel.rows()
	var sm := _row_of(panel, "smelter_scrap_mk1")
	check(sm > 0 and rows[sm - 1].get("header", "") == "Smelters", "the Slag Pot heads the Smelters group")
	_free(d)


func test_new_tags_count_and_clear_once_the_tab_was_viewed() -> void:
	var ship := Fixture.room_ship()
	var d := _panel(ship)
	var panel: CraftingPanel = d["panel"]
	eq(ship.crafting.fresh().size(), 0, "nothing is NEW at the start")
	check(ship.crafting.unlock("laser_mk2"), "learned")
	eq(ship.crafting.fresh(), ["laser_mk2"] as Array[String], "it is NEW")
	panel.open()
	eq(panel.tab_label("fabricator"), "Fabricator (1 new)", "the tab title counts it")
	check(panel.fresh_now.has("laser_mk2"), "the row carries the tag while the tab is open")
	panel.set_station("smelter")
	eq(panel.tab_label("fabricator"), "Fabricator", "gone after it was viewed")
	panel.set_station("fabricator")
	check(panel.fresh_now.is_empty(), "and the tag is gone on the next visit")
	_free(d)


func test_the_seen_set_is_saved_and_a_save_without_it_has_seen_all() -> void:
	var ship := Fixture.room_ship()
	ship.crafting.unlock("laser_mk2")
	var saved := ship.crafting.to_dict()
	check(saved.has("seen") and not saved["seen"].has("laser_mk2"), "the save lists what was seen")
	var other := Ship.new()
	eq(other.crafting.load_dict(saved), "", "loads")
	eq(other.crafting.fresh(), ["laser_mk2"] as Array[String], "the NEW one is still NEW")
	var old := saved.duplicate(true)
	old.erase("seen")
	var third := Ship.new()
	eq(third.crafting.load_dict(old), "", "an older save loads")
	eq(third.crafting.fresh().size(), 0, "and has seen everything")


func test_a_row_click_selects_it_whatever_its_station() -> void:
	var ship := Fixture.room_ship()
	var d := _panel(ship)
	var panel: CraftingPanel = d["panel"]
	panel.open()
	var r := _row_of(panel, "polymer")
	check(r >= 0, "steel is listed")
	panel.top = maxi(r - 1, 0)
	panel._gui_input(_click(panel.row_rect(r).get_center()))
	eq([panel.station, panel.selected], ["fabricator", "polymer"], "a click selects it and stays on the tab")
	r = _row_of(panel, "laser_mk1")
	panel.top = maxi(r - 1, 0)
	panel._gui_input(_click(panel.row_rect(r).get_center()))
	eq([panel.station, panel.selected], ["fabricator", "laser_mk1"], "a part too")
	eq(ship.crafting.queue.size(), 0, "and nothing was queued")
	_free(d)


func test_the_no_smelter_hint_reads_its_costs_from_the_recipe() -> void:
	var ship := Fixture.room_ship()
	var d := _panel(ship)
	var panel: CraftingPanel = d["panel"]
	var h: Dictionary = panel.no_smelter_hint(ship)
	eq(h["recipe"], "smelter_scrap_mk1", "the Slag Pot")
	var rec: Dictionary = ship.crafting.def("smelter_scrap_mk1")
	for m in rec["materials"]:
		check(h["text"].contains("%d %s" % [rec["materials"][m], ship.crafting.name_of(m).to_lower()]), "the text has " + m)
	check(h["text"].begins_with("No smelter aboard. Craft a Slag Pot at the fabricator (") and h["text"].ends_with("then place it in build mode (B)."), h["text"])
	rec["materials"]["copper"] = 3  # change the data: the text follows
	check(panel.no_smelter_hint(ship)["text"].contains("3 copper"), "the cost is not hard-coded")
	panel.open()
	panel.set_station("smelter")
	eq(panel.no_smelter_recipe(), "smelter_scrap_mk1", "the button has a recipe")
	panel._gui_input(_click(panel.hint_button_rect().get_center()))
	eq([panel.station, panel.selected], ["fabricator", "smelter_scrap_mk1"], "and opens it on the fabricator tab")
	_free(d)


func test_the_ledger_asks_for_a_slag_pot_once_there_is_scrap_and_no_smelter() -> void:
	var ship := Fixture.room_ship()
	var c := Campaign.new(5)
	var a := Advisor.new({}, {})
	ship.inventory.add("scrap", -ship.inventory.count("scrap"))
	a.update(ship, c, {})
	check(a.next_goal().get("id", "") != "x_smelter", "no goal while there is little scrap")
	ship.inventory.add("scrap", 150)
	a.update(ship, c, {})
	var g: Dictionary = a.next_goal()
	eq(g.get("id", ""), "x_smelter", "past 100 scrap with no smelter the goal is first")
	check(str(g["title"]).length() <= 130, "one short line")
	eq(g["title"], "Craft a Slag Pot: it turns scrap into steel", "its words")
	ship.inventory.add("scrap", -140)
	a.update(ship, c, {})
	eq(a.next_goal().get("id", ""), "x_smelter", "it stays once it has fired")
	var st := a.state()
	check(st["armed"].has("x_smelter"), "and is kept with the run")
	ship.inventory.add("smelter_scrap_mk1", 1)
	a.update(ship, c, {})
	check(a.next_goal().get("id", "") != "x_smelter", "a Slag Pot crafted clears it")


func test_the_learned_line_says_where_to_make_it() -> void:
	var ship := Fixture.room_ship()
	eq(ship.crafting.learned_line("laser_mk2", ship.components), "Blueprint: Laser Mk2. Make it at the fabricator (C).", "a part")
	check(ship.crafting.learned_line("steel", ship.components).ends_with("smelter (C)."), "a smelter recipe")


func test_hover_shows_a_card_and_a_click_only_selects() -> void:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "reactor_mk1", 10, 10)
	Fixture.put(ship, "fabricator", 15, 10)
	Fixture.wire(ship, [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	ship.inventory.add("scrap", 100)
	var d := _panel(ship)
	var panel: CraftingPanel = d["panel"]
	panel.open()
	var card: Dictionary = panel.hover_card("laser_mk1")
	eq(card["title"], "Laser Mk1", "the name")
	check(card["what"] != "", "what it does, from describe.json")
	var labels: Array = card["stats"].map(func(r): return r[0])
	check(labels.has("Damage") and labels.has("Every") and labels.has("Power") and labels.has("HP"), "key stats: " + str(labels))
	var rec: Dictionary = ship.crafting.def("laser_mk1")
	eq(card["mats"].size(), rec["materials"].size(), "its materials")
	for m in card["mats"]:
		eq(m[3], m[2] >= m[1], "%s is green only when the hold has it" % m[0])
	var reason: String = panel.reason("laser_mk1")
	eq(card["reason"], reason, "and the reason it cannot be queued, if any")
	check(PartCard.height(card, 330.0) > 80.0, "the card has a height")
	# a click selects and nothing is queued; Enter queues
	var id := "polymer"
	ship.inventory.add("scrap", 50)
	var r := _row_of(panel, id)
	var queue_before := ship.crafting.queue.size()
	panel.top = maxi(r - 1, 0)
	panel._gui_input(_click(panel.row_rect(r).get_center()))
	eq([panel.selected, ship.crafting.queue.size()], [id, queue_before], "a click selects, it does not queue")
	panel._gui_input(_click(panel.row_rect(r).get_center(), true))
	eq(ship.crafting.queue.size(), queue_before + 1, "a double-click queues")
	panel._input(_key(KEY_ENTER))
	eq(ship.crafting.queue.size(), queue_before + 2, "so does Enter")
	_free(d)


func test_the_fabricator_lists_only_known_recipes_and_keeps_the_unaffordable_ones() -> void:
	var ship := Fixture.room_ship()
	var d := _panel(ship)
	var panel: CraftingPanel = d["panel"]
	panel.open()
	for id in panel.recipe_ids():
		check(ship.crafting.is_known(id), id + " is known")
	var locked: Array = ship.crafting.ids().filter(func(id): return not ship.crafting.is_known(id) and ship.crafting.station_of(id) == "fabricator")
	check(not locked.is_empty() and locked.all(func(id): return not panel.recipe_ids().has(id)), "locked recipes are hidden")
	var poor: String = ""
	for id in panel.recipe_ids():
		if not ship.inventory.missing(ship.crafting.def(id)["materials"]).is_empty():
			poor = id
	if poor == "":
		for m in ship.crafting.def(panel.recipe_ids()[0])["materials"]:
			ship.inventory.counts.erase(m)
		poor = panel.recipe_ids()[0]
	check(panel.recipe_ids().has(poor), "a known recipe you cannot afford stays")
	check(not panel.card_spec(poor)["short"].is_empty(), "with its missing materials marked (red)")
	_free(d)


func test_the_fabricator_tab_counts_what_was_found() -> void:
	var ship := Fixture.room_ship()
	var d := _panel(ship)
	var panel: CraftingPanel = d["panel"]
	panel.open()
	eq(panel.found_text(), "%d of %d found" % [ship.crafting.known.size(), ship.crafting.ids().size()], "known out of all")
	var before := ship.crafting.known.size()
	var locked: Array = ship.crafting.ids().filter(func(id): return not ship.crafting.is_known(id))
	ship.crafting.unlock(locked[0])
	eq(panel.found_text(), "%d of %d found" % [before + 1, ship.crafting.ids().size()], "learning one raises the count")
	_free(d)


func test_a_recipe_card_has_no_name_and_its_hover_card_does() -> void:
	var ship := Fixture.room_ship()
	var d := _panel(ship)
	var panel: CraftingPanel = d["panel"]
	panel.open()
	var id: String = panel.recipe_ids()[0]
	var spec: Dictionary = panel.card_spec(id)
	var name: String = ship.crafting.name_of(ship.crafting.def(id)["output"]["item"], ship.components)
	check(not PicCard.labels(spec).has(name) and not spec.has("name") and not spec.has("title"), "the card prints no name")
	check(not spec["cost"].is_empty(), "it shows its materials")
	var hover: Dictionary = panel.hover_card(id)
	eq(hover["title"], name, "the hover card has the name")
	check(hover["what"] != "" or not hover["stats"].is_empty(), "and what it does")
	ship.crafting.unlock("laser_mk2")
	panel.close()
	panel.open()
	check(panel.fresh_now.has("laser_mk2") and PicCard.labels(panel.card_spec("laser_mk2")).has("NEW"), "a new blueprint's card carries NEW")
	_free(d)


func test_the_grid_scrolls_and_moves_by_lines() -> void:
	var ship := Fixture.room_ship()
	var d := _panel(ship)
	var panel: CraftingPanel = d["panel"]
	panel.open()
	var starts := panel.line_starts()
	check(starts.size() > 2, "several lines")
	panel._gui_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	eq(panel.top, starts[1], "the wheel scrolls a line")
	panel._gui_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	eq(panel.top, starts[0], "and back")
	panel.move(1000)
	check(panel.row_rect(panel.rows().size() - 1).size != Vector2.ZERO, "the last card is on screen after End")
	_free(d)


func _wheel(button: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	return e
