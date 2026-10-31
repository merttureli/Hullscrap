extends "res://tests/base_test.gd"
## Processing (docs/CONTENT.md section 12; scripts/craft/processing.gd, the smelter queue in crafting.gd, the processing_1 pack):
## the ladder's recipes, the smelter parts, queue timing and speed, a manned smelter, heat, refusals at the wrong station,
## the saves of the queue, the engine recipes re-costed with steel, and the Smelter tab of the crafting panel.

const Crafting = preload("res://scripts/craft/crafting.gd")
const Processing = preload("res://scripts/craft/processing.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")
const Content = preload("res://scripts/data/content.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const CraftingPanel = preload("res://scripts/ui/crafting_panel.gd")
const Palette = preload("res://scripts/build/palette.gd")
const Inventory = preload("res://scripts/ship/inventory.gd")

const PARTS: Array[String] = ["smelter_scrap_mk1", "smelter_mk1", "smelter_mk2", "smelter_mk3", "smelter_neon_mk1"]
const LADDER: Array[String] = ["steel", "alloy", "conductor", "glass_lattice"]


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A reactor, a smelter `id` and its cable in the test room; plenty of scrap and everything else a recipe asks for.
func _rig(id := "smelter_mk1") -> Dictionary:
	var ship := Fixture.room_ship()
	var d := {"ship": ship}
	d["reactor"] = Fixture.put(ship, "reactor_mk1", 10, 10)
	d["smelter"] = Fixture.put(ship, id, 15, 10)
	Fixture.wire(ship, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.inventory.refund({"scrap": 1000, "copper": 100, "titanium": 20, "silicon": 20, "crystal": 10})
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


func _crafting() -> Crafting:
	var c := Crafting.new()
	c.load("res://data/recipes.json", "res://data/materials.json")
	return c


func _smelter(level: int, speed := 1.0, tools := []) -> Dictionary:
	return {"station": "smelter", "level": level, "tools": tools, "speed": speed}


func _fab(level: int) -> Dictionary:
	return {"level": level, "tools": [], "modules": []}


# --- the data -------------------------------------------------------------------------------------------

func test_the_ladder_follows_the_spec() -> void:
	var c := _crafting()
	var want := {
		"steel": [{"scrap": 4}, 6.0, 1, []],
		"alloy": [{"steel": 2, "titanium": 1}, 10.0, 2, []],
		"conductor": [{"copper": 3, "silicon": 1}, 8.0, 2, []],
		"glass_lattice": [{"silicon": 2, "crystal": 1}, 12.0, 2, ["plasma"]],
	}
	for id in want:
		check(c.has(id), id + " has a recipe")
		if not c.has(id):
			continue
		var r := c.def(id)
		eq(r["station"], "smelter", id + " is a smelter recipe")
		eq(r["output"], {"item": id, "count": 1}, id + " makes one")
		eq(r["materials"], want[id][0], id + " inputs")
		eq([r["time"], r["fab_level"], r["tools"]], [want[id][1], want[id][2], want[id][3]], id + " seconds, level and tools")
		eq(r["category"], "material", id + " is a material")
		check(c.materials.has(id) and c.is_known(id), id + " is a material and its recipe is known from the start")
	eq(c.def("titanium")["station"], "fabricator", "titanium is still cut at the fabricator")
	eq(c.def("titanium")["materials"], {"scrap": 20}, "and still costs 20 scrap for 2: regional titanium keeps its value")
	eq(c.def("kickjet" if c.has("kickjet") else "engine_scrap_mk1")["station"], "fabricator", "parts are made at the fabricator")


func test_the_smelter_parts() -> void:
	var c := _crafting()
	var comps := Content.list("components")
	var by := {}
	for d in comps:
		by[d["id"]] = d
	var last_speed := 0.0
	for id in PARTS:
		check(by.has(id), id + " is a component")
		if not by.has(id):
			continue
		var d: Dictionary = by[id]
		eq(d["family"], "smelter", id + " family")
		check(d["manned"] and d["power"] < 0, id + " is crewed and draws power")
		check(float(d["heat_per_s"]) >= 8.0, id + " runs hot: heat_per_s 8 and up")
		check(d["stats"].has("work_heat") and d["stats"].has("smelt_level") and d["stats"].has("smelt_speed"), id + " has its smelting stats")
		check(c.has(id) and c.def(id)["station"] == "fabricator" and c.def(id)["category"] == "system", id + " is built at the fabricator")
	eq([by["smelter_scrap_mk1"]["line"], by["smelter_mk1"]["line"], by["smelter_mk2"]["line"], by["smelter_mk3"]["line"], by["smelter_neon_mk1"]["line"]], ["scrap", "standard", "standard", "standard", "neon"], "a Scrap Slag Pot, Standard Mk1-3, a Neon Plasma Forge")
	eq(by["smelter_scrap_mk1"]["name"], "Slag Pot", "the Slag Pot")
	eq(by["smelter_neon_mk1"]["name"], "Plasma Forge", "the Plasma Forge")
	for id in ["smelter_mk1", "smelter_mk2", "smelter_mk3"]:
		var sp: float = by[id]["stats"]["smelt_speed"]
		check(sp > last_speed, id + " is faster than the one below")
		last_speed = sp
	eq(["smelter_scrap_mk1", "smelter_mk1", "smelter_mk2", "smelter_mk3"].map(func(id): return int(by[id]["stats"]["smelt_level"])), [1, 1, 2, 3], "levels: steel at Mk1, alloy and conductor at Mk2")
	check(by["smelter_neon_mk1"]["stats"].has("plasma") and not by["smelter_mk3"]["stats"].has("plasma"), "only the Plasma Forge gives the plasma tool")
	for id in ["smelter_scrap_mk1", "smelter_mk1"]:
		check(c.is_known(id), id + " is known from the start")
	for id in ["smelter_mk2", "smelter_mk3", "smelter_neon_mk1"]:
		check(not c.is_known(id), id + " is a blueprint to find or buy")
	var ship := Ship.new()
	check(ship.effective("smelter_scrap_mk1")["stats"]["smelt_speed"] < ship.effective("smelter_mk1")["stats"]["smelt_speed"], "the Scrap line smelts slower (line output 0.9)")
	check(ship.effective("smelter_neon_mk1")["stats"]["smelt_speed"] > ship.effective("smelter_mk1")["stats"]["smelt_speed"], "and the Neon line faster (1.3)")
	check(ship.effective("smelter_neon_mk1")["heat_per_s"] > ship.effective("smelter_mk1")["heat_per_s"], "and hotter")


func test_the_armour_tiles() -> void:
	var tiles := {}
	for t in Content.list("tiles"):
		tiles[t["id"]] = t
	var f: Dictionary = tiles["forged_steel_plate"]
	eq([int(f["hp"]), f["solid"], int(f["cost"]["steel"]), int(f["cost"]["scrap"]), f["cost"].size()], [8, true, 1, 1, 2], "Forged Steel Plate: hp 8, made of steel and a little scrap")
	near(float(f["resist"]["kinetic"]), 0.7, "it takes 70% of kinetic damage (a resist of 0.3)")
	var a: Dictionary = tiles["alloy_armor"]
	eq([int(a["hp"]), a["name"]], [10, "Alloy Armour"], "Alloy Armour: hp 10")
	for t in ["kinetic", "energy", "explosive"]:
		near(float(a["resist"][t]), 0.8, "alloy takes 80% of " + t + " (an all-round resist of 0.2)")
	check(not a["resist"].has("ion"), "ion does no structural damage, so nothing resists it")
	check(float(f["mass"]) < tiles["heavy_armor"]["mass"] and float(a["mass"]) < float(f["mass"]), "lighter than Heavy Armour; alloy lighter than steel")
	var c := _crafting()
	for id in ["forged_steel_plate", "alloy_armor"]:
		for m in tiles[id]["cost"]:
			check(c.materials.has(m), id + " costs a real material " + m)
	var ship := Fixture.room_ship()
	check(ship.grid.defs.ids().has("forged_steel_plate") and ship.grid.defs.ids().has("alloy_armor"), "both are build mode tiles")


func test_the_new_materials() -> void:
	var c := _crafting()
	for id in LADDER:
		check(c.materials.has(id), id + " is a material")
		if c.materials.has(id):
			check(str(c.materials[id]["rarity"]) in ["common", "uncommon", "rare", "very_rare"] and str(c.materials[id]["name"]) != "", id + " has a name and a rarity")
	var debris: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/debris.json"))
	for t in debris["types"]:
		for m in t.get("yield", {}):
			check(not m in LADDER, "%s never floats: %s is made, not found" % [m, t["id"]])


func test_the_engine_recipes_use_the_ladder() -> void:
	var c := _crafting()
	# every Mk3+ engine of wave 1 pays steel where Mk1 and Mk2 paid scrap (scrap 40 -> steel 10); Mk4+ use alloy
	for id in ["engine_mk3", "engine_mk4", "engine_mk5", "engine_scrap_mk3", "engine_scrap_mk4", "engine_neon_mk3", "engine_neon_mk4", "strafe_jets_mk3", "longburn_mk3"]:
		check(not c.def(id)["materials"].has("scrap"), id + " uses no raw scrap")
	eq(c.def("engine_mk3")["materials"]["steel"], 10, "scrap 40 became steel 10")
	for id in ["engine_mk4", "engine_mk5", "engine_scrap_mk4", "engine_neon_mk4"]:
		check(c.def(id)["materials"].has("alloy"), id + " (Mk4+) uses alloy")
	for id in ["engine_neon_mk2", "engine_neon_mk3", "engine_neon_mk4"]:
		check(c.def(id)["materials"].has("glass_lattice") and not c.def(id)["materials"].has("crystal"), id + " (Neon Mk2+) uses glass lattice")
	for id in ["engine_mk1", "engine_mk2", "engine_scrap_mk1", "engine_scrap_mk2", "engine_neon_mk1"]:
		check(c.def(id)["materials"].has("scrap") or id == "engine_neon_mk1", id + " (Mk1, Mk2) keeps raw scrap")
	var o := Content.overrides().filter(func(x): return x["pack"] == "processing_1")
	eq(o.size(), 10, "ten overrides, each with a reason")
	for x in o:
		check(str(x["reason"]).begins_with("CONTENT 12"), x["id"] + " says why")


func test_a_recost_keeps_the_raw_materials() -> void:
	# smelting 4 scrap -> 1 steel, 2 steel + 1 titanium -> 1 alloy, 2 silicon + 1 crystal -> 1 glass lattice: the raw bill never grows
	var c := _crafting()
	var base := {}
	for r in Content.read("res://data/packs/engines_1/recipes.json")["recipes"]:
		base[r["id"]] = r["materials"]
	for id in ["engine_mk3", "engine_mk4", "engine_mk5", "engine_scrap_mk3", "engine_scrap_mk4", "engine_neon_mk2", "engine_neon_mk3", "engine_neon_mk4", "strafe_jets_mk3", "longburn_mk3"]:
		var raw := {}
		for m in c.def(id)["materials"]:
			var n: int = c.def(id)["materials"][m]
			match m:
				"steel":
					raw["scrap"] = int(raw.get("scrap", 0)) + 4 * n
				"alloy":
					raw["scrap"] = int(raw.get("scrap", 0)) + 8 * n
					raw["titanium"] = int(raw.get("titanium", 0)) + n
				"glass_lattice":
					raw["silicon"] = int(raw.get("silicon", 0)) + 2 * n
					raw["crystal"] = int(raw.get("crystal", 0)) + n
				_:
					raw[m] = int(raw.get(m, 0)) + n
		for m in base[id]:
			var was: int = base[id][m]
			if m == "scrap":
				check(int(raw.get("scrap", 0)) >= was and int(raw.get("scrap", 0)) < was + 4 * 3, "%s: scrap %d is about %d" % [id, int(raw.get("scrap", 0)), was])
			else:
				eq(int(raw.get(m, 0)), was, "%s: %s is unchanged" % [id, m])


# --- the queue: refusals, timing, speed ------------------------------------------------------------------

func test_a_smelter_recipe_is_refused_at_the_fabricator_and_the_reverse() -> void:
	var d := _rig()
	var ship: Ship = d["ship"]
	Fixture.put(ship, "fabricator", 15, 13)
	Fixture.wire(ship, [Vector2i(13, 13), Vector2i(14, 13), Vector2i(15, 13)])
	ship.refresh()
	var fab := Workshop.best(ship)
	check(fab["level"] >= 1, "there is a working fabricator")
	var scrap := ship.inventory.count("scrap")
	eq(ship.crafting.enqueue("steel", ship.inventory, fab), "needs a smelter", "the fabricator will not smelt")
	eq(ship.crafting.can_craft("steel", ship.inventory, fab), "needs a smelter", "can_craft says the same")
	eq([ship.inventory.count("scrap"), ship.crafting.queue.size(), ship.crafting.queue_of("smelter").size()], [scrap, 0, 0], "nothing was paid or queued")
	eq(ship.crafting.enqueue("polymer", ship.inventory, Processing.best(ship)), "needs a fabricator", "and the smelter will not craft")
	eq(ship.crafting.enqueue("steel", ship.inventory, Processing.best(ship)), "", "the smelter takes it")
	eq([ship.crafting.queue.size(), ship.crafting.queue_of("smelter").size(), ship.inventory.count("scrap")], [0, 1, scrap - 4], "into its own queue, paid up front")


func test_levels_tools_power_and_materials_gate_a_job() -> void:
	var c := _crafting()
	var inv := _inv({"scrap": 100, "steel": 10, "titanium": 5, "silicon": 5, "crystal": 5, "copper": 10})
	eq(c.can_craft("steel", inv, {"station": "smelter", "level": 0, "tools": []}), "smelter offline", "no powered smelter")
	eq(c.can_craft("steel", inv, _smelter(1)), "", "level 1 smelts steel")
	eq(c.can_craft("alloy", inv, _smelter(1)), "needs smelter level 2", "alloy needs Mk2")
	eq(c.can_craft("conductor", inv, _smelter(1)), "needs smelter level 2", "so does conductor")
	eq(c.can_craft("alloy", inv, _smelter(2)), "", "Mk2 does alloy")
	eq(c.can_craft("glass_lattice", inv, _smelter(2)), "needs tool: plasma", "glass lattice needs a Plasma Forge")
	eq(c.can_craft("glass_lattice", inv, _smelter(2, 1.3, ["plasma"])), "", "with one")
	eq(c.can_craft("steel", _inv({"scrap": 3}), _smelter(1)), "missing: 1 scrap", "the missing scrap is named")


func _inv(cargo: Dictionary) -> Inventory:
	var i := Inventory.new()
	i.refund(cargo)
	return i


func test_queue_timing_speed_and_carry() -> void:
	var c := _crafting()
	var inv := _inv({"scrap": 100})
	for i in 3:
		eq(c.enqueue("steel", inv, _smelter(1)), "", "queued")
	eq(inv.count("scrap"), 88, "4 scrap each, up front")
	eq(c.tick(5.9, inv, _smelter(1)), [] as Array[String], "not done after 5.9 s")
	eq(c.tick(0.2, inv, _smelter(1)), ["steel"] as Array[String], "done at 6 s")
	near(c.queue_of("smelter")[0]["progress"], 0.1, "and 0.1 s carries into the next job")
	# a faster smelter: x1.3 does 6 s of work in 4.6 s
	eq(c.tick(4.5, inv, _smelter(1, 1.3)).size(), 0, "a Mk2 (x1.3) needs 4.54 s for what is left, not 4.5")
	eq(c.tick(0.1, inv, _smelter(1, 1.3)).size(), 1, "and has it by 4.6 s")
	near(c.queue_of("smelter")[0]["progress"], 0.1 + 4.6 * 1.3 - 6.0, "with the spare work on the next")
	var slow := _crafting()
	var inv2 := _inv({"scrap": 100})
	slow.enqueue("steel", inv2, _smelter(1, 0.9))
	eq(slow.tick(6.5, inv2, _smelter(1, 0.9)), [] as Array[String], "a Slag Pot (x0.9) is not done at 6.5 s")
	eq(slow.tick(0.3, inv2, _smelter(1, 0.9)), ["steel"] as Array[String], "but is at 6.8 s")
	eq(inv2.count("steel"), 1, "one steel in the cargo")
	var q := _crafting()
	var inv3 := _inv({"scrap": 1000})
	for i in Crafting.QUEUE_MAX:
		eq(q.enqueue("steel", inv3, _smelter(1)), "", "job %d" % i)
	eq(q.enqueue("steel", inv3, _smelter(1)), "queue full", "eight at most")
	eq(inv3.count("scrap"), 1000 - 4 * Crafting.QUEUE_MAX, "and the refused one cost nothing")
	check(q.cancel(0, inv3, "smelter"), "cancel the first")
	eq(inv3.count("scrap"), 1000 - 4 * (Crafting.QUEUE_MAX - 1), "its scrap is back")
	check(not q.cancel(99, inv3, "smelter"), "no such job")
	eq(q.queue.size(), 0, "the fabricator's queue was never touched")


func test_the_sim_smelts_into_the_cargo_and_the_chronicle_says_so() -> void:
	var d := _rig()
	var ship: Ship = d["ship"]
	var sim := _sim(ship)
	var scrap := ship.inventory.count("scrap")
	eq(ship.crafting.enqueue("steel", ship.inventory, Processing.best(ship)), "", "queued")
	eq(ship.crafting.enqueue("steel", ship.inventory, Processing.best(ship)), "", "twice")
	_run(sim, 5.5)
	eq(ship.inventory.count("steel"), 0, "nothing at 5.5 s")
	_run(sim, 0.5)
	eq(ship.inventory.count("steel"), 1, "one steel at 6 s")
	_run(sim, 6.0)
	eq([ship.inventory.count("steel"), ship.inventory.count("scrap"), ship.crafting.queue_of("smelter").size()], [2, scrap - 8, 0], "two at 12 s, 8 scrap spent")
	eq(_texts(ship).count("Smelted Steel"), 2, "the chronicle: %s" % [_texts(ship)])
	sim.free()


func test_a_better_smelter_is_faster_and_alloy_needs_mk2() -> void:
	var d := _rig("smelter_mk2")
	var ship: Ship = d["ship"]
	var st := Processing.best(ship)
	eq([st["level"], st["tools"], st["count"], st["uid"]], [2, [], 1, d["smelter"]], "a Smelter Mk2 is level 2")
	near(st["speed"], 1.3, "and 1.3 fast")
	ship.inventory.refund({"steel": 4})
	eq(ship.crafting.enqueue("alloy", ship.inventory, st), "", "alloy is possible")
	var sim := _sim(ship)
	_run(sim, 7.5)
	eq(ship.inventory.count("alloy"), 0, "10 s of work is not done at 7.5 s")
	_run(sim, 0.5)
	eq([ship.inventory.count("alloy"), ship.inventory.count("steel"), ship.inventory.count("titanium")], [1, 2, 19], "but is at 8 s (10 / 1.3): 2 steel and 1 titanium became 1 alloy")
	sim.free()
	var weak := _rig("smelter_scrap_mk1")
	eq(Processing.best(weak["ship"])["level"], 1, "a Slag Pot is level 1")
	eq(weak["ship"].crafting.enqueue("alloy", weak["ship"].inventory, Processing.best(weak["ship"])), "needs smelter level 2", "and cannot alloy")
	near(Processing.best(weak["ship"])["speed"], 0.9, "at 0.9 speed")


func test_the_plasma_forge_makes_glass_lattice() -> void:
	var d := _rig("smelter_neon_mk1")
	var ship: Ship = d["ship"]
	var st := Processing.best(ship)
	eq([st["level"], st["tools"]], [2, ["plasma"]], "level 2 with the plasma tool")
	near(st["speed"], 1.3, "Neon output x1.3")
	eq(ship.crafting.enqueue("glass_lattice", ship.inventory, st), "", "queued")
	eq([ship.inventory.count("silicon"), ship.inventory.count("crystal")], [18, 9], "2 silicon and 1 crystal paid")
	var sim := _sim(ship)
	_run(sim, 9.5)
	eq(ship.inventory.count("glass_lattice"), 1, "12 s of work in 9.2 s")
	sim.free()


func test_several_smelters_share_a_queue_and_pool_their_levels_and_tools() -> void:
	var d := _rig("smelter_mk1")
	var ship: Ship = d["ship"]
	var forge := Fixture.put(ship, "smelter_neon_mk1", 15, 13)
	Fixture.wire(ship, [Vector2i(13, 13), Vector2i(14, 13), Vector2i(15, 13)])
	ship.refresh()
	var st := Processing.best(ship)
	eq([st["level"], st["tools"], st["count"], st["uid"]], [2, ["plasma"], 2, forge], "the Forge leads (fastest) and the level and tools pool")
	ship.cables.cells.erase(Vector2i(15, 13))
	ship.cables.cells.erase(Vector2i(14, 13))
	ship.mark_dirty()
	ship.refresh()
	st = Processing.best(ship)
	eq([st["level"], st["tools"], st["count"], st["uid"]], [1, [], 2, d["smelter"]], "an unwired one does not count")
	ship.cables.cells.clear()
	ship.mark_dirty()
	st = Processing.best(ship)
	eq([st["level"], st["uid"], st["speed"], st["count"]], [0, -1, 0.0, 2], "no power: level 0")
	var sim := _sim(ship)
	ship.crafting.enqueue("steel", ship.inventory, _smelter(1))
	_run(sim, 3.0)
	check(ship.crafting.is_paused("smelter"), "an unpowered smelter pauses its queue")
	near(ship.crafting.queue_of("smelter")[0]["progress"], 0.0, "and nothing moves")
	eq(_texts(ship).count("Smelter offline: smelting paused"), 1, "the chronicle says so once")
	sim.free()


# --- crew ----------------------------------------------------------------------------------------------------

func _npc(p_name: String, x: int, y: int) -> CrewMember:
	return CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)))


func test_a_crew_member_mans_a_busy_smelter_and_it_works_30_percent_faster() -> void:
	var d := _rig()
	var ship: Ship = d["ship"]
	var uid: int = d["smelter"]
	var jobs := Jobs.new()
	ship.crew.append(_npc("Ada", 13, 14))
	jobs.build_board(ship)
	check(not jobs.board.has("post:%d" % uid), "an idle smelter has no post: nobody waits at it")
	var sim := _sim(ship)
	near(Processing.best(ship)["speed"], 1.0, "unmanned: speed 1")
	check(not Processing.best(ship)["manned"], "not manned")
	for i in 4:
		ship.crafting.enqueue("steel", ship.inventory, Processing.best(ship))
	_run(sim, 1.0)
	jobs.build_board(ship)
	check(jobs.board.has("post:%d" % uid), "a queued smelter gets a post")
	eq(jobs.board["post:%d" % uid]["priority"], 50, "at 50: it keeps its priority out of a fight, level with the helm")
	jobs.combat = true
	jobs.build_board(ship)
	eq(jobs.board["post:%d" % uid]["priority"], 45, "and gives way to the guns (50) in a fight")
	jobs.combat = false
	_run(sim, 5.0)
	check(ship.manned.has(uid), "Ada went to the smelter: %s" % str(ship.manned))
	var st := Processing.best(ship)
	check(st["manned"], "so it counts as manned")
	near(st["speed"], 1.3, "and works at x1.3")
	sim.free()
	# the same ship without a crew member takes the full 12 s for two steels
	var alone := _rig()
	var asim := _sim(alone["ship"])
	alone["ship"].crafting.enqueue("steel", alone["ship"].inventory, Processing.best(alone["ship"]))
	alone["ship"].crafting.enqueue("steel", alone["ship"].inventory, Processing.best(alone["ship"]))
	_run(asim, 11.5)
	eq(alone["ship"].inventory.count("steel"), 1, "alone: one steel at 11.5 s")
	asim.free()


func test_the_post_goes_away_when_the_queue_is_empty_or_the_smelter_is_not_the_lead() -> void:
	var d := _rig()
	var ship: Ship = d["ship"]
	var uid: int = d["smelter"]
	var other := Fixture.put(ship, "smelter_scrap_mk1", 15, 13)
	Fixture.wire(ship, [Vector2i(13, 13), Vector2i(14, 13), Vector2i(15, 13)])
	ship.refresh()
	var sim := _sim(ship)
	ship.crafting.enqueue("steel", ship.inventory, Processing.best(ship))
	_run(sim, 1.0)
	check(Processing.post_wanted(ship, uid), "the lead smelter wants a crew member")
	check(not Processing.post_wanted(ship, other), "the slower one does not")
	check(Processing.post_wanted(ship, Fixture.put(ship, "helm", 19, 13)), "any other post always does")
	_run(sim, 6.0)
	check(not Processing.post_wanted(ship, uid), "and nobody is wanted once the queue is done")
	sim.free()


# --- heat ----------------------------------------------------------------------------------------------------

func test_a_smelter_only_heats_while_it_works() -> void:
	var d := _rig()
	var ship: Ship = d["ship"]
	var sim := _sim(ship)
	_run(sim, 20.0)
	near(float(ship.components.instances[d["smelter"]]["heat"]), 0.0, "idle: no heat")
	ship.crafting.enqueue("steel", ship.inventory, Processing.best(ship))
	ship.crafting.enqueue("steel", ship.inventory, Processing.best(ship))
	_run(sim, 12.0)
	var h: float = ship.components.instances[d["smelter"]]["heat"]
	check(h > 50.0 and h < 62.0, "12 s of work gains about (8 - 3) a second: %s" % h)
	_run(sim, 10.0)
	check(float(ship.components.instances[d["smelter"]]["heat"]) < h - 20.0, "and it cools once the work is done")
	sim.free()


func test_a_smelter_without_a_radiator_overheats_on_a_long_queue_and_a_radiator_fixes_it() -> void:
	var hot := _rig()
	var ship: Ship = hot["ship"]
	for i in 6:
		ship.crafting.enqueue("steel", ship.inventory, Processing.best(ship))
	var sim := _sim(ship)
	var tripped := false
	for i in 80:
		sim.step(0.5)
		if ship.components.instances[hot["smelter"]]["status"] == "overheated":
			tripped = true
			break
	check(tripped, "36 s of smelting trips the limit without a radiator")
	check(_texts(ship).has("Smelter Mk1 overheated"), "the chronicle says so: %s" % [_texts(ship)])
	sim.free()
	var cool := _rig()
	var s2: Ship = cool["ship"]
	Fixture.put(s2, "radiator", 19, 10)
	Fixture.wire(s2, [Vector2i(18, 11), Vector2i(19, 11)])
	s2.refresh()
	for i in 6:
		s2.crafting.enqueue("steel", s2.inventory, Processing.best(s2))
	var sim2 := _sim(s2)
	_run(sim2, 40.0)
	eq(s2.inventory.count("steel"), 6, "with a radiator beside it all six come out")
	eq(s2.components.instances[cool["smelter"]]["status"], "ok", "and it never overheated")
	sim2.free()


# --- saves ---------------------------------------------------------------------------------------------------

func test_the_smelter_queue_survives_a_save() -> void:
	var d := _rig()
	var ship: Ship = d["ship"]
	ship.crafting.enqueue("steel", ship.inventory, Processing.best(ship))
	ship.crafting.enqueue("steel", ship.inventory, Processing.best(ship))
	ship.crafting.enqueue("polymer", ship.inventory, _fab(1))
	var sim := _sim(ship)
	_run(sim, 3.0)
	sim.free()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))
	check(saved["crafting"].has("queues") and saved["crafting"]["queues"].has("smelter"), "the smelter's jobs are in the save")
	var back := Ship.new_starter()
	eq(back.load_dict(saved), "", "it loads")
	var jobs: Array = back.crafting.queue_of("smelter")
	eq(jobs.size(), 2, "both jobs are back")
	eq(jobs[0]["recipe"], "steel", "in order")
	near(jobs[0]["progress"], 3.0, "with the work done so far", 0.01)
	eq(jobs[0]["paid"], {"scrap": 4}, "and what was paid")
	eq([back.crafting.queue.size(), back.crafting.queue[0]["recipe"]], [1, "polymer"], "the fabricator's queue is its own")
	# an empty smelter queue is not written at all, so a save from before this one is the same shape
	var fresh := Ship.new_starter()
	check(not fresh.to_dict()["crafting"].has("queues"), "no queues key when no station but the fabricator has work")
	var plain: Dictionary = fresh.to_dict()
	eq(fresh.load_dict(plain), "", "and loads")
	eq(fresh.crafting.queue_of("smelter").size(), 0, "with an empty smelter queue")


func test_a_broken_station_queue_is_refused() -> void:
	var ship := Ship.new_starter()
	var base: Dictionary = ship.crafting.to_dict()
	var job := {"recipe": "steel", "progress": 1.0, "paid": {"scrap": 4}}
	var bad := base.duplicate(true)
	bad["queue"] = [job]
	eq(ship.crafting.check_dict(bad), "job steel is in the wrong queue", "a smelter job in the fabricator's queue")
	bad = base.duplicate(true)
	bad["queues"] = {"smelter": [{"recipe": "polymer", "progress": 0.0, "paid": {"scrap": 3, "copper": 1}}]}
	eq(ship.crafting.check_dict(bad), "job polymer is in the wrong queue", "and a fabricator job in the smelter's")
	bad["queues"] = {"furnace": []}
	eq(ship.crafting.check_dict(bad), "unknown station furnace", "an unknown station")
	bad["queues"] = {"fabricator": []}
	eq(ship.crafting.check_dict(bad), "unknown station fabricator", "the fabricator's queue is `queue`")
	bad["queues"] = {"smelter": "steel"}
	eq(ship.crafting.check_dict(bad), "bad job list", "a queue that is not a list")
	bad["queues"] = {"smelter": [job, job, job, job, job, job, job, job, job]}
	eq(ship.crafting.check_dict(bad), "queue too long", "nine jobs")
	bad["queues"] = {"smelter": [job]}
	eq(ship.crafting.check_dict(bad), "", "one good job")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ships/starter_courier.json"))
	eq(Ship.new_starter().load_dict(raw), "", "a design with no smelter queue still loads")


# --- the palette and the panel ---------------------------------------------------------------------------------

func test_the_smelters_are_on_the_utility_tab_and_say_what_they_smelt() -> void:
	var ship := Ship.new_starter()
	for id in PARTS:
		eq(Palette.component_tab(ship.components.def(id)), Palette.Tab.UTILITY, id + " is a Utility part")
	var rows: Array = Palette.info(Palette.part_entry(ship, "smelter_neon_mk1"), ship)["rows"].filter(func(r): return r[0] == "Smelts")
	eq(rows.size(), 1, "a Smelts row")
	check(str(rows[0][1]).contains("level 2") and str(rows[0][1]).contains("plasma"), "level and tool: " + str(rows[0]))


func _panel(ship: Ship) -> Dictionary:
	var sim := _sim(ship)
	var panel := CraftingPanel.new()
	panel.sim = sim
	panel.size = Vector2(1600.0, 900.0)
	return {"panel": panel, "sim": sim}


func _free(d: Dictionary) -> void:
	d["panel"].free()
	d["sim"].free()


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


func test_the_panel_has_a_smelter_tab_with_its_own_recipes_and_queue() -> void:
	var rig := _rig()
	var ship: Ship = rig["ship"]
	var d := _panel(ship)
	var panel: CraftingPanel = d["panel"]
	var scrap := ship.inventory.count("scrap")
	panel.open()
	eq(panel.station, "fabricator", "opens on the fabricator")
	check(not panel.recipe_ids().has("steel") and panel.recipe_ids().has("polymer"), "no smelter recipes on the fabricator tab")
	panel._input(_key(KEY_TAB))
	eq(panel.station, "smelter", "Tab switches to the smelter")
	eq(panel.recipe_ids(), ["steel", "alloy", "conductor", "glass_lattice"] as Array[String], "its ladder, in order")
	eq(panel.selected, "steel", "the cursor is on the first")
	eq(panel.reason("steel"), "", "steel can be queued")
	eq(panel.reason("alloy"), "needs smelter level 2", "alloy cannot, on a Mk1")
	eq(panel.craft("steel"), "", "queued")
	eq([ship.crafting.queue_of("smelter").size(), ship.crafting.queue.size(), panel.message], [1, 0, "Queued Steel"], "in the smelter's queue")
	check(panel.craft("polymer") != "", "a fabricator recipe is refused here")
	var jr: Rect2 = panel.job_rect(0)
	eq(panel.job_at(jr.get_center()), 0, "the job is under the mouse")
	panel._gui_input(_click(jr.get_center()))
	eq([ship.crafting.queue_of("smelter").size(), ship.inventory.count("scrap")], [0, scrap], "a click cancels it, the scrap comes back")
	panel._input(_key(KEY_TAB))
	eq(panel.station, "fabricator", "Tab again goes back")
	panel._gui_input(_click(panel.tab_rect(1).get_center()))
	eq(panel.station, "smelter", "and the tab button switches too")
	check(not panel.set_station("furnace"), "an unknown tab is refused")
	panel.next_station()
	eq(panel.station, "fabricator", "next_station wraps round")
	_free(d)
