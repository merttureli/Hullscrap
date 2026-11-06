extends "res://tests/base_test.gd"
## The crafting screen after the Fabricator and Blueprints tabs were merged: the Upgrade button in the fabricator's box, the merged list
## (known but not makeable yet: marked, with the reason), and the real pictures of gear, guns and tools on item cards.

const CraftingPanel = preload("res://scripts/ui/crafting_panel.gd")
const PicCard = preload("res://scripts/ui/pic_card.gd")
const Thumbs = preload("res://scripts/ui/thumbs.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Crafting = preload("res://scripts/craft/crafting.gd")
const Inventory = preload("res://scripts/ship/inventory.gd")
const Processing = preload("res://scripts/craft/processing.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")

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


# --- batches --------------------------------------------------------------------------------------------------------------

const FAB := {"level": 4, "tools": ["laser_cutter", "nanoforge"], "speed": 1.0}


func _bench(stock: Dictionary) -> Array:
	var c := Crafting.new()
	c.load("res://data/recipes.json", "res://data/materials.json")
	c.unlock("polymer")
	var inv := Inventory.new()
	inv.load_dict(stock)
	return [c, inv]


func _unit(c: Crafting) -> Dictionary:
	return c.def("polymer")["materials"]


func test_a_batch_of_five_makes_five_and_pays_one_unit_at_a_time() -> void:
	var b := _bench({"scrap": 1000, "copper": 100, "titanium": 100})
	var c: Crafting = b[0]
	var inv: Inventory = b[1]
	var m := _unit(c)
	var scrap0 := inv.count("scrap")
	eq(c.enqueue("polymer", inv, FAB, 5), "", "queued")
	eq(scrap0 - inv.count("scrap"), int(m["scrap"]), "only the first unit is paid")
	var t: float = c.def("polymer")["time"]
	var made := 0
	for i in 5:
		made += c.tick(t + 0.01, inv, FAB).size()
	eq(made, 5, "five units are made")
	eq(c.queue.size(), 0, "and the job is gone")
	eq(scrap0 - inv.count("scrap"), 5 * int(m["scrap"]), "five units were paid in all")
	eq(inv.count("polymer"), 5 * int(c.def("polymer")["output"]["count"]), "in the cargo")


func test_a_batch_waits_when_short_and_resumes_and_others_carry_on() -> void:
	var b := _bench({"scrap": 100000, "copper": 100000, "titanium": 100000})
	var c: Crafting = b[0]
	var inv: Inventory = b[1]
	c.unlock("titanium")
	var m := _unit(c)
	var stock := {}
	for k in m:
		stock[k] = int(m[k])  # exactly one unit of polymer
	inv.load_dict({})
	inv.add(m.keys()[0], 0)
	for k in stock:
		inv.add(k, stock[k])
	eq(c.enqueue("polymer", inv, FAB, 3), "", "queued with exactly one unit")
	var t: float = c.def("polymer")["time"]
	c.tick(t + 0.01, inv, FAB)
	var job: Dictionary = c.queue[0]
	eq(int(job["done"]), 1, "one made")
	check(job.has("wait") and not job["wait"].is_empty(), "the job waits for the next unit")
	var first: String = m.keys()[0]
	eq(job["wait"].keys().has(first) or job["wait"].size() > 0, true, "and knows what is short")
	# a second job behind it with other materials carries on
	var other := _bench({})
	var tt := c.def("titanium")
	var need: Dictionary = tt["materials"]
	for k in need:
		inv.add(k, int(need[k]) * 2)
	eq(c.enqueue("titanium", inv, FAB, 1), "", "a job behind it")
	var got := c.tick(float(tt["time"]) + 0.01, inv, FAB)
	check(got.has("titanium"), "the one behind carries on while the first waits")
	check(c.queue.size() == 1 and c.queue[0]["recipe"] == "polymer", "the waiting job stays first")
	for k in m:
		inv.add(k, int(m[k]) * 2)  # the cargo has them again
	var more := 0
	for i in 3:
		more += c.tick(t + 0.01, inv, FAB).size()
	eq(more, 2, "it resumes by itself and finishes the other two units")
	eq(c.queue.size(), 0, "done")


func test_cancel_mid_batch_refunds_one_unit() -> void:
	var b := _bench({"scrap": 1000, "copper": 100, "titanium": 100})
	var c: Crafting = b[0]
	var inv: Inventory = b[1]
	var m := _unit(c)
	var scrap0 := inv.count("scrap")
	c.enqueue("polymer", inv, FAB, 5)
	var t: float = c.def("polymer")["time"]
	c.tick(t + 0.01, inv, FAB)
	c.tick(t * 0.4, inv, FAB)  # the second unit is half-made, paid
	eq(int(c.queue[0]["done"]), 1, "one done")
	check(c.cancel(0, inv), "cancelled")
	eq(scrap0 - inv.count("scrap"), 1 * int(m["scrap"]), "two units were paid, one came back: the finished one stays paid")
	eq(c.queue.size(), 0, "gone")


func test_repeat_runs_until_cancelled() -> void:
	var b := _bench({"scrap": 100000, "copper": 100000, "titanium": 100000})
	var c: Crafting = b[0]
	var inv: Inventory = b[1]
	c.enqueue("polymer", inv, FAB, 0)
	var t: float = c.def("polymer")["time"]
	var made := 0
	for i in 150:
		made += c.tick(t + 0.01, inv, FAB).size()
	eq(made, 150, "far past 99 and still going")
	eq(c.queue.size(), 1, "the job stays")
	check(c.cancel(0, inv), "until cancelled")
	eq(c.queue.size(), 0, "gone")


func test_a_saved_job_keeps_its_count_and_an_old_one_loads_as_one() -> void:
	var b := _bench({"scrap": 1000, "copper": 100, "titanium": 100})
	var c: Crafting = b[0]
	var inv: Inventory = b[1]
	c.enqueue("polymer", inv, FAB, 20)
	c.tick(float(c.def("polymer")["time"]) * 2.5, inv, FAB)
	var saved := c.to_dict()
	eq([saved["queue"][0]["count"], saved["queue"][0]["done"]], [20, 2], "the save has count and done")
	var d := Crafting.new()
	d.load("res://data/recipes.json", "res://data/materials.json")
	eq(d.load_dict(saved), "", "loads")
	eq([d.queue[0]["count"], d.queue[0]["done"]], [20, 2], "and keeps them")
	var old := {"version": 1, "known": ["polymer"], "queue": [{"recipe": "polymer", "progress": 1.0, "paid": {"scrap": 20}}]}
	var e := Crafting.new()
	e.load("res://data/recipes.json", "res://data/materials.json")
	eq(e.load_dict(old), "", "a version 1 save loads")
	eq([e.queue[0]["count"], e.queue[0]["done"]], [1, 0], "its job is a batch of 1")


func test_the_panel_batch_picker_the_cost_line_and_the_queue_rows() -> void:
	var d := _panel({"scrap": 500, "copper": 100, "titanium": 100})
	var panel: CraftingPanel = d["panel"]
	var ship: Ship = d["ship"]
	panel.open()
	var id := "polymer"
	panel.selected = id
	panel.set_batch(20)
	eq(panel.batch, 20, "20")
	var rec: Dictionary = ship.crafting.def(id)
	check(panel.batch_text(id).begins_with("Batch of 20: %d scrap" % (20 * int(rec["materials"]["scrap"]))), panel.batch_text(id))
	check(panel.batch_text(id).ends_with("You can afford %d now." % panel.afford_count(id)), "it says how many you can afford: " + panel.batch_text(id))
	panel._gui_input(_click(panel.batch_button_rect(3).get_center()))
	eq(panel.batch, 20, "the 20 button")
	panel._gui_input(_click(panel.batch_button_rect(4).get_center()))
	eq(panel.batch, 40, "the 40 button")
	panel._gui_input(_click(panel.batch_button_rect(5).get_center()))
	eq(panel.batch, 0, "Repeat")
	panel.step_batch(-1)
	eq(panel.batch, 99, "the wheel steps down from Repeat")
	panel.step_batch(1)
	eq(panel.batch, 99, "to 99 at most")
	panel.set_batch(20)
	eq(panel.craft(id), "", "queues")
	var job: Dictionary = ship.crafting.queue[0]
	eq([job["count"], job["done"]], [20, 0], "a job of 20")
	eq(panel.job_label(job), "Polymer 0/20", "the row says so")
	job["done"] = 7
	eq(panel.job_label(job), "Polymer 7/20", "7 of 20")
	job["count"] = 0
	eq(panel.job_label(job), "Polymer 7/\u221e", "7 of repeat")
	job["wait"] = {"scrap": 3}
	eq(panel.wait_text(job), "Waiting: 3 scrap short", "and why it waits")
	_free(d)


# --- smelter upgrade ------------------------------------------------------------------------------------------------------

## A ship with a fabricator (level `fab_level`), a reactor, and a smelter `id` at (15, 14), with plenty of everything.
func _smelt(id: String, fab_level := 4) -> Dictionary:
	var d := _panel({"scrap": 1000, "copper": 200, "titanium": 100, "silicon": 50, "conductor": 50, "polymer": 50, "alloy": 100, "crystal": 50})
	var ship: Ship = d["ship"]
	ship.components.instances[d["fab"]]["fab_level"] = fab_level
	d["smelter"] = Fixture.put(ship, id, 15, 14)
	for k in ["smelter_mk1", "smelter_mk2", "smelter_mk3"]:
		ship.crafting.unlock(k)
	ship.refresh()
	return d


func test_the_smelter_upgrade_swaps_the_part_in_place() -> void:
	var d := _smelt("smelter_mk1")
	var panel: CraftingPanel = d["panel"]
	var ship: Ship = d["ship"]
	panel.open()
	panel.set_station("smelter")
	var inf := panel.smelter_upgrade()
	eq([inf["next"], inf["can"]], ["smelter_mk2", true], "next is Mk2 and it can go")
	check(str(inf["text"]).contains("level 2") and str(inf["text"]).contains("1.3"), "it says what it adds: " + str(inf["text"]))
	eq(panel.smelter_label(), "Upgrade to Smelter Mk2", "the button")
	var old: Dictionary = ship.components.instances[d["smelter"]]
	var anchor: Vector2i = old["anchor"]
	var rot: int = old["rot"]
	var scrap := ship.inventory.count("scrap")
	eq(ship.crafting.enqueue("steel", ship.inventory, {"station": "smelter", "level": 3, "tools": [], "count": 1}, 3), "", "a smelter job is queued")
	panel._gui_input(_click(panel.upgrade_rect().get_center()))
	var uid := Processing.upgrade_uid(ship)
	eq(ship.components.instances[uid]["id"], "smelter_mk2", "swapped for Mk2")
	eq([ship.components.instances[uid]["anchor"], ship.components.instances[uid]["rot"]], [anchor, rot], "in the same place and rotation")
	check(ship.inventory.count("smelter_mk1") >= 1, "the old smelter is in the cargo")
	eq(ship.inventory.count("scrap"), scrap - int(ship.crafting.def("smelter_mk2")["materials"]["scrap"]) - int(ship.crafting.def("steel")["materials"]["scrap"]), "the recipe's materials were paid")
	eq(ship.crafting.queue_of("smelter").size(), 1, "the queue survived")
	check(panel.flash > 0.0 and not panel.message_bad, "with the flash and a message: " + panel.message)
	check(ship.events.any(func(e): return str(e["text"]).contains("upgraded to Smelter Mk2")), "and a log line")
	_free(d)


func test_the_smelter_upgrade_is_refused_for_each_reason() -> void:
	var d := _smelt("smelter_mk1", 1)
	var panel: CraftingPanel = d["panel"]
	var ship: Ship = d["ship"]
	panel.open()
	panel.set_station("smelter")
	eq(panel.smelter_label(), "Needs fabricator level 2", "the fabricator is too low for Mk2")
	ship.components.instances[d["fab"]]["fab_level"] = 4
	ship.crafting.known.erase("smelter_mk2")
	eq(panel.smelter_label(), "Blueprint not found yet", "no blueprint")
	ship.crafting.unlock("smelter_mk2")
	ship.inventory.counts.erase("titanium")
	check(panel.smelter_label().begins_with("Short: ") and panel.smelter_label().contains("titanium"), "short: " + panel.smelter_label())
	var before := ship.inventory.count("scrap")
	eq(panel.upgrade_smelter() != "", true, "a click is refused")
	eq([ship.inventory.count("scrap"), Processing.upgrade_uid(ship) == d["smelter"]], [before, true], "and pays and changes nothing")
	_free(d)


func test_slag_pot_to_mk1_needs_a_free_column() -> void:
	var d := _smelt("smelter_scrap_mk1")
	var panel: CraftingPanel = d["panel"]
	var ship: Ship = d["ship"]
	panel.open()
	var old: Dictionary = ship.components.instances[d["smelter"]]
	eq(old["cells"].size(), 9, "the Slag Pot is 3x3")
	eq(panel.smelter_upgrade()["can"], true, "with a free column it can go")
	# block both sides with parts
	var a: Vector2i = old["anchor"]
	var blockers := [Fixture.put(ship, "robot_arm", a.x + 3, a.y), Fixture.put(ship, "robot_arm", a.x - 2, a.y)]
	var inf := panel.smelter_upgrade()
	check(not inf["can"] and inf["why"] == "Needs one more free column of floor beside it", "blocked: " + str(inf["why"]))
	check(blockers[0] >= 0 and blockers[1] >= 0, "the blockers were placed (fixture)")
	check(str(inf["text"]).contains("Clear"), "the details say what to clear: " + str(inf["text"]))
	_free(d)


func test_slag_pot_to_mk1_grows_into_the_free_column() -> void:
	var d := _smelt("smelter_scrap_mk1")
	var ship: Ship = d["ship"]
	var a: Vector2i = ship.components.instances[d["smelter"]]["anchor"]
	eq(Processing.upgrade(ship, d["smelter"]), "", "swapped")
	var uid := Processing.upgrade_uid(ship)
	eq(ship.components.instances[uid]["id"], "smelter_mk1", "Mk1")
	eq(ship.components.instances[uid]["cells"].size(), 12, "4x3")
	eq(ship.components.instances[uid]["anchor"], a, "it grew to the right, the Slag Pot's own cells are still covered")
	check(ship.inventory.count("smelter_scrap_mk1") >= 1, "the Slag Pot is in the cargo")
	_free(d)


func test_an_item_with_no_art_and_no_icon_falls_back_to_the_cargo_crate() -> void:
	eq(Thumbs.icon_id("basic_armor"), "cargo", "no art, no icon: the crate")
	eq(Thumbs.icon_id("fuel"), "fuel", "an icon of its own is kept")
	eq(Thumbs.icon_id("titanium"), "titanium", "so is a material's")
	var d := _panel({})
	var panel: CraftingPanel = d["panel"]
	panel.open()
	eq(panel.card_spec("basic_armor")["entry"], {"kind": "item", "id": "cargo"}, "the recipe card too")
	_free(d)


func test_an_unpowered_smelter_says_why_not_that_there_is_none() -> void:
	var d := _smelt("smelter_mk1")
	var panel: CraftingPanel = d["panel"]
	var ship: Ship = d["ship"]
	check(panel.off_text(ship, "smelter") == "Smelter Mk1 has no power: cable it to a reactor.", panel.off_text(ship, "smelter"))
	ship.components.instances[d["smelter"]]["status"] = "disabled"
	check(panel.off_text(ship, "smelter").ends_with("is disabled: repair it."), panel.off_text(ship, "smelter"))
	ship.components.remove_uid(d["smelter"])
	check(panel.off_text(ship, "smelter").begins_with("No smelter. Build one"), "none aboard")
	_free(d)
