extends "res://tests/base_test.gd"

const Crafting = preload("res://scripts/craft/crafting.gd")
const Components = preload("res://scripts/ship/components.gd")
const Inventory = preload("res://scripts/ship/inventory.gd")

const RECIPES := "res://data/recipes.json"
const MATERIALS := "res://data/materials.json"
const ITEMS := "res://data/items.json"
const ITEM_KINDS := ["ammo", "gear", "special"]
## Mk1 parts of the standard line that are blueprints to find, not known at the start (every other
## Mk1 Scrap or Standard system is known; Neon is always unlocked).
const MK1_TO_UNLOCK: Array[String] = ["pulse_mk1", "ion_blast_mk1", "artemis_mk1"]
const RARITIES := ["common", "uncommon", "rare", "very_rare"]
const CATEGORIES := ["system", "gear", "material", "module"]
const WORKSHOP_TOOLS := ["laser_cutter", "nanoforge"]  # what workshop.gd can provide
## Scrap and Neon line parts and the radiator, added with the lines (docs/CONTENT.md step 1): they
## have no recipe yet. Remove an id from here when its recipe is added.
const NO_RECIPE_YET: Array[String] = []


func _crafting() -> Crafting:
	var c := Crafting.new()
	c.load(RECIPES, MATERIALS)
	return c


func _comps() -> Components:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	return c


## data/items.json: item id -> {id, name, kind, blurb}.
func _items() -> Dictionary:
	var out := {}
	for i in JSON.parse_string(FileAccess.get_file_as_string(ITEMS))["items"]:
		out[i["id"]] = i
	return out


func _inv(cargo: Dictionary) -> Inventory:
	var i := Inventory.new()
	i.refund(cargo)
	return i


func _fab(level: int, tools := []) -> Dictionary:
	return {"level": level, "tools": tools, "modules": []}


## Enough of everything for the tests that are not about money.
func _rich() -> Inventory:
	return _inv({"scrap": 1000, "copper": 1000, "titanium": 100, "silicon": 100, "polymer": 100, "crystal": 10, "plasma_cell": 10, "nanite_paste": 10})


func _ids(d: Dictionary) -> Array:
	var a := d.keys()
	a.sort()
	return a


# --- data consistency -------------------------------------------------------------------------

func test_every_component_has_a_recipe() -> void:
	var c := _crafting()
	var comps := _comps()
	for id in comps.ids():
		if id in NO_RECIPE_YET:
			continue
		if comps.def(id).get("unique", false):
			check(not c.has(id), "unique %s has no recipe" % id)
			continue
		check(c.has(id), "component %s has a recipe" % id)
		if c.has(id):
			var r := c.def(id)
			eq(r["output"]["item"], id, id + " recipe makes the part")
			eq(r["output"]["count"], 1, id + " recipe makes one")
			eq(r["category"], "module" if comps.def(id)["family"] == "workshop" else "system", id + " category")


func test_recipe_data_is_valid() -> void:
	var c := _crafting()
	var comps := _comps()
	var items := _items()
	var mats: Array = JSON.parse_string(FileAccess.get_file_as_string(MATERIALS))["materials"]
	eq(c.materials.size(), mats.size(), "material ids are unique")
	for m in mats:
		for k in ["id", "name", "color", "rarity"]:
			check(m.has(k), "material %s has %s" % [m.get("id", "?"), k])
		check(RARITIES.has(m["rarity"]), "%s rarity %s is known" % [m["id"], m["rarity"]])
	for id in ["scrap", "copper", "titanium", "silicon", "polymer", "crystal", "plasma_cell", "nanite_paste"]:
		check(c.materials.has(id), "material " + id)
	check(c.ids().size() > 0, "there are recipes")
	for id in c.ids():
		var r := c.def(id)
		eq(r["id"], id, "id")
		check(CATEGORIES.has(r["category"]), "%s category %s is known" % [id, r["category"]])
		var item: String = r["output"]["item"]
		check(r["output"]["count"] >= 1, id + " makes at least one")
		match r["category"]:
			"system", "module":
				check(comps.has(item), "%s output %s is a component" % [id, item])
				eq(comps.def(item).get("family", "") == "workshop", r["category"] == "module", id + " module iff workshop family")
			"material":
				check(c.materials.has(item), "%s output %s is a material" % [id, item])
			"gear":
				check(not comps.has(item) and not c.materials.has(item), "%s gear id %s is neither part nor material" % [id, item])
				check(items.has(item) and items[item]["kind"] in ["gear", "ammo"], "%s output %s is a gear or ammo item" % [id, item])
		check(not r["materials"].is_empty(), id + " costs something")
		for m in r["materials"]:
			check(c.materials.has(m), "%s material %s exists" % [id, m])
			check(r["materials"][m] > 0, "%s needs a positive %s" % [id, m])
		check(r["fab_level"] >= 1 and r["fab_level"] <= 4, id + " fab_level is 1 to 4")
		check(r["time"] > 0.0, id + " takes time")
		for t in r["tools"]:
			check(WORKSHOP_TOOLS.has(t), "%s tool %s can be provided" % [id, t])
	# other data that names materials stays valid too
	for t in JSON.parse_string(FileAccess.get_file_as_string("res://data/tiles.json"))["tiles"]:
		for m in t.get("cost", {}):
			check(c.materials.has(m), "tile %s costs a known material %s" % [t["id"], m])
	for m in JSON.parse_string(FileAccess.get_file_as_string("res://data/start.json"))["cargo"]:
		check(c.materials.has(m) or c.has(m), "start cargo %s is a known id" % m)


func test_the_numbers_follow_the_brief() -> void:
	var c := _crafting()
	for id in ["reactor_mk1", "engine_mk1", "oxygen_gen", "shield_mk1", "laser_mk1", "helm", "medbay", "bed", "fabricator"]:
		eq(c.def(id)["fab_level"], 1, id + " is level 1")
		eq(_ids(c.def(id)["materials"]), ["copper", "scrap"], id + " is scrap and copper")
	check(c.def("engine_mk2")["fab_level"] in [2, 3] and c.def("engine_mk2")["materials"].has("titanium"), "engine_mk2")
	eq(c.def("laser_mk2")["tools"], ["laser_cutter"], "laser_mk2 needs the cutter")
	check(c.def("laser_mk2")["fab_level"] in [2, 3], "laser_mk2 level")
	eq(c.def("reactor_mk2")["fab_level"], 3, "reactor_mk2 is level 3")
	check(c.def("reactor_mk2")["materials"].has("plasma_cell"), "reactor_mk2 needs a plasma cell")
	eq([c.def("robot_arm")["fab_level"], c.def("laser_cutter")["fab_level"], c.def("assembly_rig")["fab_level"], c.def("nanoforge")["fab_level"]], [1, 2, 2, 3], "module levels")
	check(c.def("nanoforge")["materials"].has("nanite_paste"), "nanoforge needs nanite paste")
	eq([c.def("pistol")["fab_level"], c.def("rifle")["fab_level"], c.def("basic_armor")["fab_level"], c.def("eva_suit")["fab_level"]], [1, 2, 1, 2], "gear levels")
	var ti := c.def("titanium")
	eq(ti["materials"], {"scrap": 5}, "titanium: 5 scrap")
	eq(ti["output"], {"item": "titanium", "count": 2}, "titanium: makes 2")
	eq([ti["fab_level"], ti["tools"]], [2, ["laser_cutter"]], "titanium: level 2 with the cutter")
	var p := c.def("polymer")
	eq(p["materials"], {"scrap": 3, "copper": 1}, "polymer: 3 scrap and 1 copper")
	eq([p["output"], p["fab_level"], p["tools"]], [{"item": "polymer", "count": 1}, 1, []], "polymer: one at level 1")


func test_start_blueprints() -> void:
	var c := _crafting()
	var comps := _comps()
	for id in ["reactor_mk1", "engine_mk1", "oxygen_gen", "shield_mk1", "laser_mk1", "helm", "medbay", "bed", "fabricator", "robot_arm", "pistol", "basic_armor", "polymer"]:
		check(c.is_known(id), id + " is known at the start")
	# rule: every Mk1 Scrap or Standard system is known from the start; Neon must be unlocked (PLAN: equipment lines)
	for id in comps.ids():
		var d: Dictionary = comps.def(id)
		if d.get("unique", false):
			check(not c.is_known(id), "unique %s has no blueprint" % id)
		elif d["family"] != "workshop" and d["tier"] == 1 and not id in NO_RECIPE_YET:
			if d.get("line", "standard") == "neon" or id in MK1_TO_UNLOCK:
				check(not c.is_known(id), "Neon system %s must be unlocked" % id)
			else:
				check(c.is_known(id), "Mk1 system %s is known" % id)
	for id in ["engine_mk2", "laser_mk2", "reactor_mk2", "laser_cutter", "assembly_rig", "nanoforge", "rifle", "eva_suit", "titanium", "pulse_mk2", "shield_mk2", "missile"]:
		check(not c.is_known(id), id + " must be unlocked")
	check(c.queue.is_empty(), "nothing queued")
	for id in c.ids():
		check(not id.contains("exo") and not id.contains("unique"), "no recipe for special gear: " + id)


func test_unlock() -> void:
	var c := _crafting()
	check(not c.is_known("nanoforge"), "not known yet")
	check(c.unlock("nanoforge"), "unlocked")
	check(c.is_known("nanoforge"), "known now")
	check(not c.unlock("nanoforge"), "unlocking twice is refused")
	check(not c.unlock("helm"), "a start blueprint is already known")
	check(not c.unlock("warp_core"), "an unknown recipe is refused")
	check(not c.known.has("warp_core"), "and not added")


# --- items and the weapons content pack -------------------------------------------------------

func test_items_data() -> void:
	var c := _crafting()
	var comps := _comps()
	var raw: Array = JSON.parse_string(FileAccess.get_file_as_string(ITEMS))["items"]
	var items := _items()
	eq(items.size(), raw.size(), "item ids are unique")
	for id in items:
		var i: Dictionary = items[id]
		for k in ["id", "name", "kind", "blurb"]:
			check(i.has(k) and str(i[k]) != "", "item %s has %s" % [id, k])
		check(i.get("kind", "") in ITEM_KINDS, "item %s kind %s is known" % [id, i.get("kind", "")])
		check(not comps.has(id) and not c.materials.has(id), "item %s is not also a part or a material" % id)
	for id in ["missile"]:
		eq(items[id]["kind"], "ammo", id + " is ammo")
	for id in ["pistol", "rifle", "basic_armor", "eva_suit"]:
		eq(items[id]["kind"], "gear", id + " is gear")
	for id in ["exosuit", "salamander_suit", "heat_suit", "plasma_rifle"]:
		eq(items[id]["kind"], "special", id + " is special")


func test_every_recipe_output_exists() -> void:
	var c := _crafting()
	var comps := _comps()
	var items := _items()
	for id in c.ids():
		var item: String = c.def(id)["output"]["item"]
		check(comps.has(item) or c.materials.has(item) or items.has(item), "%s output %s is a part, a material or an item" % [id, item])


func test_special_items_and_uniques_have_no_recipe() -> void:
	var c := _crafting()
	var comps := _comps()
	for id in _items():
		if _items()[id]["kind"] == "special":
			check(not c.has(id), "special item %s has no recipe" % id)
			check(not c.known.has(id), "special item %s is not a start blueprint" % id)
	for id in c.ids():
		check(not _items().has(c.def(id)["output"]["item"]) or _items()[c.def(id)["output"]["item"]]["kind"] != "special", "%s does not make a special item" % id)
	for id in comps.ids():
		if comps.def(id).get("unique", false):
			check(not c.has(id), "unique %s has no recipe" % id)
	for id in ["leech_laser", "breach_harpoon", "mirror_veil"]:
		check(not c.has(id), id + " is found, not built")


func test_missile_recipe() -> void:
	var c := _crafting()
	var r := c.def("missile")
	eq(r["output"], {"item": "missile", "count": 2}, "two missiles per job")
	eq(r["materials"], {"scrap": 4, "copper": 2, "polymer": 1}, "missile cost")
	eq([r["fab_level"], r["tools"], r["category"]], [2, [], "gear"], "missile: level 2, no tool, an item")


func test_weapon_and_shield_recipes_follow_the_lines() -> void:
	var c := _crafting()
	var comps := _comps()
	var n := 0
	for id in comps.ids():
		var d: Dictionary = comps.def(id)
		if d["family"] != "weapon" and d["family"] != "shield":
			continue
		if d.get("unique", false) or id in ["laser_mk1", "laser_mk2", "shield_mk1"]:
			continue
		n += 1
		var r := c.def(id)
		check(not r.is_empty(), id + " has a recipe")
		if r.is_empty():
			continue
		var total := 0
		for m in r["materials"]:
			total += int(r["materials"][m])
		match d["line"]:
			"scrap":
				eq(r["fab_level"], 1, id + ": scrap is level 1")
				check(int(r["materials"].get("scrap", 0)) * 2 > total, id + ": scrap is mostly scrap")
				check(d["tier"] != 1 or c.is_known(id), id + ": a scrap Mk1 is known at the start")
			"standard":
				check(r["fab_level"] in [1, 2], id + ": standard is level 1 or 2")
			"neon":
				eq(r["fab_level"], 3, id + ": neon is level 3")
				check("laser_cutter" in r["tools"], id + ": neon needs the laser cutter")
				check(r["materials"].has("silicon") or r["materials"].has("crystal"), id + ": neon needs silicon or crystal")
				check(not c.is_known(id), id + ": neon must be unlocked")
		eq(r["output"]["count"], 1, id + " makes one")
		eq(r["category"], "system", id + " is a system")
	check(n >= 12, "the pack's twelve craftable parts are all covered")


# --- can_craft --------------------------------------------------------------------------------

func test_can_craft_reasons_in_priority_order() -> void:
	var c := _crafting()
	var empty := _inv({})
	eq(c.can_craft("warp_core", empty, _fab(0)), "unknown recipe", "unknown recipe beats everything")
	eq(c.can_craft("laser_mk2", empty, _fab(0)), "blueprint not known", "blueprint beats an offline fabricator")
	c.unlock("laser_mk2")
	eq(c.can_craft("laser_mk2", empty, _fab(0)), "fabricator offline", "offline beats level")
	eq(c.can_craft("laser_mk2", empty, {}), "fabricator offline", "an empty fab is offline")
	eq(c.can_craft("laser_mk2", empty, _fab(1)), "needs fabricator level 2", "level beats tool")
	eq(c.can_craft("laser_mk2", empty, _fab(2)), "needs tool: laser_cutter", "tool beats materials")
	eq(c.can_craft("laser_mk2", empty, _fab(2, ["nanoforge"])), "needs tool: laser_cutter", "the wrong tool")
	eq(c.can_craft("laser_mk2", empty, _fab(2, ["laser_cutter"])), "missing: 20 scrap, 10 copper, 6 titanium, 4 silicon", "all of it, in recipe order")
	var some := _inv({"scrap": 25, "copper": 10, "titanium": 3})
	eq(c.can_craft("laser_mk2", some, _fab(2, ["laser_cutter"])), "missing: 3 titanium, 4 silicon", "only what is short")
	var all := _inv({"scrap": 20, "copper": 10, "titanium": 6, "silicon": 4})
	eq(c.can_craft("laser_mk2", all, _fab(2, ["laser_cutter"])), "", "affordable")
	eq(c.can_craft("laser_mk2", all, _fab(4, ["laser_cutter", "nanoforge"])), "", "a better fabricator is fine")
	c.unlock("reactor_mk2")
	var short := _inv({"scrap": 40, "titanium": 9, "silicon": 6, "plasma_cell": 1})
	eq(c.can_craft("reactor_mk2", short, _fab(3)), "missing: 3 titanium, 1 plasma_cell", "reactor_mk2 shortfall")
	eq(c.can_craft("helm", _inv({"scrap": 10, "copper": 6}), _fab(1)), "", "a level 1 part at level 1")


# --- the queue --------------------------------------------------------------------------------

func test_enqueue_spends_and_cancel_refunds() -> void:
	var c := _crafting()
	var inv := _inv({"scrap": 100, "copper": 30})
	eq(c.enqueue("engine_mk1", inv, _fab(1)), "", "queued")
	eq(inv.count("scrap"), 80, "scrap spent at once")
	eq(inv.count("copper"), 20, "copper spent at once")
	eq(c.queue.size(), 1, "one job")
	eq(c.enqueue("laser_mk2", inv, _fab(1)), "blueprint not known", "refused jobs say why")
	eq(inv.count("scrap"), 80, "and cost nothing")
	eq(c.queue.size(), 1, "and are not queued")
	check(not c.cancel(3, inv), "no such job")
	check(not c.cancel(-1, inv), "no such job (negative)")
	eq(inv.count("scrap"), 80, "a bad cancel refunds nothing")
	check(c.cancel(0, inv), "cancelled")
	eq(inv.to_dict(), {"scrap": 100, "copper": 30}, "refunded in full")
	check(c.queue.is_empty(), "queue empty")


func test_cancel_a_job_in_the_middle() -> void:
	var c := _crafting()
	var inv := _rich()
	c.enqueue("helm", inv, _fab(1))
	c.enqueue("bed", inv, _fab(1))
	c.enqueue("engine_mk1", inv, _fab(1))
	var scrap := inv.count("scrap")
	check(c.cancel(1, inv), "bed cancelled")
	eq(inv.count("scrap"), scrap + 8, "the bed's scrap came back")
	eq([c.queue[0]["recipe"], c.queue[1]["recipe"]], ["helm", "engine_mk1"], "order kept")


func test_queue_is_limited() -> void:
	var c := _crafting()
	var inv := _rich()
	for i in Crafting.QUEUE_MAX:
		eq(c.enqueue("helm", inv, _fab(1)), "", "job %d queued" % i)
	var scrap := inv.count("scrap")
	eq(c.enqueue("helm", inv, _fab(1)), "queue full", "the ninth is refused")
	eq(inv.count("scrap"), scrap, "and costs nothing")
	eq(c.queue.size(), Crafting.QUEUE_MAX, "still eight")
	c.cancel(0, inv)
	eq(c.enqueue("helm", inv, _fab(1)), "", "a free slot again")


func test_tick_completes_and_outputs_the_item() -> void:
	var c := _crafting()
	var inv := _rich()
	c.enqueue("helm", inv, _fab(1))  # 8 seconds
	eq(c.tick(3.0, inv, _fab(1)), [] as Array[String], "not done yet")
	eq(c.queue[0]["progress"], 3.0, "3 seconds in")
	eq(inv.count("helm"), 0, "no item yet")
	eq(c.tick(4.0, inv, _fab(1)), [] as Array[String], "still not")
	eq(c.tick(1.0, inv, _fab(1)), ["helm"] as Array[String], "done on the dot")
	eq(inv.count("helm"), 1, "the helm is in cargo")
	check(c.queue.is_empty(), "queue empty")
	eq(c.tick(5.0, inv, _fab(1)), [] as Array[String], "an empty queue ticks quietly")
	# a recipe that makes more than one
	var cutter := _fab(2, ["laser_cutter"])
	c.unlock("titanium")
	var scrap := inv.count("scrap")
	eq(c.enqueue("titanium", inv, cutter), "", "refining queued")
	eq(inv.count("scrap"), scrap - 5, "5 scrap in")
	var ti := inv.count("titanium")
	eq(c.tick(100.0, inv, cutter), ["titanium"] as Array[String], "refined")
	eq(inv.count("titanium"), ti + 2, "2 titanium out")


func test_queue_pauses_when_the_fabricator_drops_and_resumes() -> void:
	var c := _crafting()
	var inv := _rich()
	c.unlock("laser_mk2")
	var good := _fab(2, ["laser_cutter"])  # laser_mk2: level 2, laser_cutter, 30 s
	eq(c.enqueue("laser_mk2", inv, good), "", "queued")
	c.tick(10.0, inv, good)
	eq(c.queue[0]["progress"], 10.0, "10 s done")
	eq(c.tick(100.0, inv, _fab(0)), [] as Array[String], "power lost: nothing")
	eq(c.queue[0]["progress"], 10.0, "paused at level 0")
	c.tick(100.0, inv, _fab(1))
	eq(c.queue[0]["progress"], 10.0, "paused below the needed level")
	c.tick(100.0, inv, _fab(3))
	eq(c.queue[0]["progress"], 10.0, "paused without the tool")
	c.tick(100.0, inv, {})
	eq(c.queue[0]["progress"], 10.0, "paused on an empty fab")
	check(inv.count("laser_mk2") == 0, "nothing was made")
	eq(c.tick(15.0, inv, good), [] as Array[String], "power back: 15 more seconds")
	eq(c.queue[0]["progress"], 25.0, "resumed from 10")
	eq(c.tick(5.0, inv, _fab(4, ["laser_cutter", "nanoforge"])), ["laser_mk2"] as Array[String], "a better fabricator finishes it")
	eq(inv.count("laser_mk2"), 1, "made")


func test_two_jobs_finish_in_order() -> void:
	var c := _crafting()
	var inv := _rich()
	c.enqueue("helm", inv, _fab(1))  # 8 s
	c.enqueue("bed", inv, _fab(1))   # 6 s
	eq(c.tick(7.0, inv, _fab(1)), [] as Array[String], "first still running")
	eq(c.queue.size(), 2, "both queued")
	eq(c.tick(3.0, inv, _fab(1)), ["helm"] as Array[String], "helm first")
	eq(c.queue.size(), 1, "bed is next")
	eq(c.queue[0]["recipe"], "bed", "the bed")
	eq(c.queue[0]["progress"], 2.0, "the spare 2 s went into the bed")
	eq(inv.count("bed"), 0, "no bed yet")
	eq(c.tick(4.0, inv, _fab(1)), ["bed"] as Array[String], "bed second")
	check(inv.count("helm") == 1 and inv.count("bed") == 1, "both in cargo")
	# one big step finishes everything
	c.enqueue("helm", inv, _fab(1))
	c.enqueue("bed", inv, _fab(1))
	eq(c.tick(100.0, inv, _fab(1)), ["helm", "bed"] as Array[String], "in order")


func test_a_blocked_next_job_waits_for_its_fabricator() -> void:
	var c := _crafting()
	var inv := _rich()
	c.unlock("laser_mk2")
	var good := _fab(2, ["laser_cutter"])
	c.enqueue("helm", inv, good)
	c.enqueue("laser_mk2", inv, good)
	eq(c.tick(100.0, inv, _fab(1)), ["helm"] as Array[String], "the helm finishes")
	eq(c.queue.size(), 1, "the laser waits")
	eq(c.queue[0]["progress"], 0.0, "and got none of the spare time")
	eq(c.tick(100.0, inv, good), ["laser_mk2"] as Array[String], "then it runs")


# --- saving -----------------------------------------------------------------------------------

func test_save_and_load_keep_blueprints_and_progress() -> void:
	var c := _crafting()
	var inv := _rich()
	c.unlock("laser_mk2")
	c.unlock("nanoforge")
	var good := _fab(2, ["laser_cutter"])
	c.enqueue("laser_mk2", inv, good)  # 30 s
	c.enqueue("helm", inv, good)       # 8 s
	c.tick(12.5, inv, good)
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	var back := _crafting()
	eq(back.load_dict(d), "", "loads")
	eq(back.known, c.known, "same blueprints")
	check(back.is_known("nanoforge"), "the unlocked blueprint is back")
	eq(back.queue.size(), 2, "both jobs")
	eq(back.queue[0]["recipe"], "laser_mk2", "order kept")
	eq(back.queue[0]["progress"], 12.5, "progress kept")
	eq(back.queue[1]["progress"], 0.0, "second job untouched")
	eq(back.to_dict(), c.to_dict(), "dicts match")
	var inv2 := _inv({})
	eq(back.tick(17.0, inv2, good), [] as Array[String], "17 s: 29.5 of 30")
	eq(back.tick(0.5, inv2, good), ["laser_mk2"] as Array[String], "done after the remaining 17.5 s")
	eq(inv2.count("laser_mk2"), 1, "the item arrives")
	check(back.cancel(0, inv2), "cancel the helm")
	eq(inv2.count("scrap"), 10, "the saved cost is refunded")
	eq(inv2.count("copper"), 6, "the saved cost is refunded")


func test_load_dict_refuses_bad_saves_and_changes_nothing() -> void:
	var c := _crafting()
	var inv := _rich()
	c.enqueue("helm", inv, _fab(1))
	var before := c.to_dict()
	check(c.load_dict({"version": 99, "known": [], "queue": []}) != "", "future version")
	check(c.load_dict({"version": 1, "known": ["warp_core"], "queue": []}) != "", "unknown blueprint")
	check(c.load_dict({"version": 1, "known": [], "queue": [{"recipe": "warp_core", "progress": 0, "paid": {}}]}) != "", "unknown job")
	check(c.load_dict({"version": 1, "known": [], "queue": [{"recipe": "helm", "progress": -1, "paid": {}}]}) != "", "negative progress")
	check(c.load_dict({"version": 1, "known": [], "queue": [{"recipe": "helm", "progress": 0, "paid": {"scrap": -3}}]}) != "", "negative cost")
	check(c.load_dict({"version": 1, "known": [], "queue": [{"recipe": "helm", "progress": 0}]}) != "", "no cost")
	var long := []
	for i in Crafting.QUEUE_MAX + 1:
		long.append({"recipe": "helm", "progress": 0, "paid": {}})
	check(c.load_dict({"version": 1, "known": [], "queue": long}) != "", "queue too long")
	eq(c.to_dict(), before, "nothing changed")
	eq(c.load_dict({"version": 1, "known": ["helm"], "queue": []}), "", "an empty queue is fine")
	eq(_ids(c.known), ["helm"], "known replaced")
	check(c.queue.is_empty(), "queue replaced")
