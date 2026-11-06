extends "res://tests/base_test.gd"
## The crafting screen after the Fabricator and Blueprints tabs were merged: the Upgrade button in the fabricator's box, the merged list
## (known but not makeable yet: marked, with the reason), and the real pictures of gear, guns and tools on item cards.

const CraftingPanel = preload("res://scripts/ui/crafting_panel.gd")
const PicCard = preload("res://scripts/ui/pic_card.gd")
const Thumbs = preload("res://scripts/ui/thumbs.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")

const STOCK := {"scrap": 1000, "copper": 100, "titanium": 100, "silicon": 50, "conductor": 50, "polymer": 50, "alloy": 100, "crystal": 50}


func _panel(stock: Dictionary) -> Dictionary:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "reactor_mk1", 10, 10)
	var fab := Fixture.put(ship, "fabricator", 15, 10)
	Fixture.wire(ship, [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	ship.inventory.load_dict(stock)
	var sim := ShipSim.new()
	sim.ships = [ship]
	var panel := CraftingPanel.new()
	panel.sim = sim
	panel.size = Vector2(1600.0, 900.0)
	return {"panel": panel, "sim": sim, "ship": ship, "fab": fab}


func _free(d: Dictionary) -> void:
	d["panel"].free()
	d["sim"].free()


func _click(p: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	return e


func test_the_upgrade_button_pays_and_raises_the_level() -> void:
	var d := _panel(STOCK)
	var panel: CraftingPanel = d["panel"]
	var ship: Ship = d["ship"]
	panel.open()
	var inf := panel.fab_upgrade()
	eq([inf["level"], inf["next"]], [1, 2], "level 1, next 2")
	eq(panel.upgrade_label(), "Upgrade to level 2", "the button")
	check(str(inf["text"]).begins_with("Level 2:") and str(inf["text"]).contains("more blueprint"), "it says what level 2 opens: " + str(inf["text"]))
	var scrap := ship.inventory.count("scrap")
	panel._gui_input(_click(panel.upgrade_rect().get_center()))
	eq(int(ship.components.instances[d["fab"]]["fab_level"]), 2, "one click upgrades")
	eq(ship.inventory.count("scrap"), scrap - 80, "and pays 80 scrap")
	check(panel.flash > 0.0 and panel.message == "Fabricator upgraded to level 2" and not panel.message_bad, "with a flash and a message")
	check(ship.events.any(func(e): return str(e["text"]).contains("Fabricator upgraded to level 2")), "and a log line")
	_free(d)


func test_a_short_hold_disables_the_button_and_says_what_is_missing() -> void:
	var d := _panel({"scrap": 80, "copper": 30, "titanium": 7})
	var panel: CraftingPanel = d["panel"]
	var ship: Ship = d["ship"]
	panel.open()
	check(not panel.fab_upgrade()["can"], "cannot")
	eq(panel.upgrade_label(), "Need 1 titanium", "it says what is missing")
	panel._gui_input(_click(panel.upgrade_rect().get_center()))
	eq(int(ship.components.instances[d["fab"]]["fab_level"]), 1, "a click does nothing")
	eq(ship.inventory.count("scrap"), 80, "and pays nothing")
	check(panel.message_bad, "it says so")
	eq(panel.upgrade_fab() != "", true, "upgrade_fab refuses too")
	_free(d)


func test_no_button_at_level_four() -> void:
	var d := _panel(STOCK)
	var panel: CraftingPanel = d["panel"]
	var ship: Ship = d["ship"]
	panel.open()
	for lv in 3:
		eq(panel.upgrade_fab(), "", "up")
	eq(int(ship.components.instances[d["fab"]]["fab_level"]), 4, "level 4")
	eq(panel.fab_upgrade()["next"], 0, "no next level")
	eq(panel.upgrade_label(), "", "no button text")
	var scrap := ship.inventory.count("scrap")
	panel._gui_input(_click(panel.upgrade_rect().get_center()))
	eq(ship.inventory.count("scrap"), scrap, "a click where it was pays nothing")
	_free(d)


func test_the_merged_list_marks_what_cannot_be_made_yet() -> void:
	var d := _panel({"scrap": 100})
	var panel: CraftingPanel = d["panel"]
	var ship: Ship = d["ship"]
	panel.open()
	var ids := panel.recipe_ids()
	var known_fab: Array = ship.crafting.known.keys().filter(func(id): return ship.crafting.station_of(id) == "fabricator" and id != "fabricator")
	eq(ids.size(), known_fab.size(), "every known fabricator blueprint, once")
	var high := ""
	for id in ids:
		if int(ship.crafting.def(id)["fab_level"]) > 1:
			high = id
	if high == "":
		high = "laser_mk2"
		ship.crafting.unlock(high)
		panel.close()
		panel.open()
	check(panel.recipe_ids().has(high), "a known blueprint above the level is listed")
	var spec: Dictionary = panel.card_spec(high)
	check(spec["dim"] and spec["meta_bad"], "dimmed, its level in red")
	check(str(panel.reason(high)).begins_with("needs fabricator level"), "and the reason: " + panel.reason(high))
	var poor := ""
	for id in ids:
		if int(ship.crafting.def(id)["fab_level"]) == 1 and not ship.inventory.missing(ship.crafting.def(id)["materials"]).is_empty():
			poor = id
	check(poor != "" and panel.card_spec(poor)["dim"] and not panel.card_spec(poor)["short"].is_empty(), "an unaffordable one is dimmed with its missing materials")
	var ok := ""
	for id in ids:
		if panel.reason(id) == "":
			ok = id
	check(ok != "" and not panel.card_spec(ok)["dim"], "a makeable one is not")
	eq(panel.craft(ok), "", "and queues")
	eq(ship.crafting.queue.size(), 1, "in the fabricator's queue")
	check(not ids.has("fabricator"), "the fabricator's own recipe is hidden on a ship that has one")
	check(ids.all(func(id): return ship.crafting.is_known(id)), "nothing unfound")
	eq(panel.found_text(), "%d of %d found" % [ship.crafting.known.size(), ship.crafting.ids().size()], "the found count")
	_free(d)


func test_there_are_two_tabs_and_tab_cycles() -> void:
	eq(CraftingPanel.STATION_IDS, ["fabricator", "smelter"] as Array[String], "Fabricator and Smelter")
	var d := _panel({})
	var panel: CraftingPanel = d["panel"]
	panel.open()
	panel.next_station()
	eq(panel.station, "smelter", "Tab")
	panel.next_station()
	eq(panel.station, "fabricator", "and back")
	check(panel.help_lines().any(func(l): return l.contains("Upgrade")), "the help mentions the Upgrade button")
	_free(d)


func test_the_picture_of_an_item_is_its_sprite_else_the_icon() -> void:
	var gun := Thumbs.item_art("pistol")
	eq([gun.get("kind"), gun.get("path")], ["items", "res://art/items/pistol.png"], "a hand gun draws its art/items sprite")
	var suit := Thumbs.item_art("eva_suit")
	eq([suit.get("kind"), suit.get("path")], ["gear", "res://art/gear/eva_suit.png"], "worn gear its art/gear sprite")
	var rig := Thumbs.item_art("rigger_harness")
	eq(rig.get("kind"), "gear", "gear made per rig too")
	check(Thumbs.item_art("titanium").is_empty(), "a material has no sprite: the UI icon is used")
	check(Thumbs.item_art("no_such_item").is_empty(), "nor an unknown id")


func test_a_known_item_with_art_gets_an_item_card() -> void:
	var d := _panel({})
	var panel: CraftingPanel = d["panel"]
	var ship: Ship = d["ship"]
	panel.open()
	var got := false
	for id in ship.crafting.known:
		var out := str(ship.crafting.def(id)["output"]["item"])
		if not Thumbs.item_art(out).is_empty() and not ship.components.has(out):
			eq(panel.card_spec(id)["entry"], {"kind": "item", "id": out}, id + " gets its own picture")
			got = true
	check(got, "at least one known recipe has an item with art")
	_free(d)
