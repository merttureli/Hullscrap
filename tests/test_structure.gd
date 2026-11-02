extends "res://tests/base_test.gd"
## Structure (scripts/ship/structure.gd, data/structure.json): there is no hull-health pool. A ship's structure is the hp of its
## blocks over their maximum, never shown; below the defeat line a ship in a fight is wrecked; nothing but the damaged blocks is
## carried between fights; events and drift jumps hurt outer blocks; a station mends every block; the top bar shows a wrench
## with the number of damaged blocks instead of a hull figure.

const Structure = preload("res://scripts/ship/structure.gd")
const StructureUtil = preload("res://tests/structure_util.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Damage = preload("res://scripts/combat/damage.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Audio = preload("res://scripts/audio/audio.gd")
const Ambience = preload("res://scripts/audio/ambience.gd")

const WALLS := 184.0  ## the room ship: 46 walls of 4 hp round its room


## The fixture room ship (46 walls) with a reactor (8 hp) inside.
func _ship() -> Ship:
	var s := Fixture.room_ship()
	Fixture.put(s, "reactor_mk1", 12, 11)
	return s


func _campaign(seed_value := 1) -> Campaign:
	var c := Campaign.new(seed_value)
	c.cfg = c.cfg.duplicate(true)
	return c


func test_the_defeat_line_is_data() -> void:
	check(Structure.defeat_below() >= 0.4 and Structure.defeat_below() <= 0.6, "data/structure.json: defeat_below is tuned between 0.4 and 0.6")
	check(Structure.config().has("_doc"), "and it says what it is")


func test_structure_is_the_hp_of_the_blocks_over_their_maximum() -> void:
	var s := _ship()
	var reactor: int = s.components.instances.keys()[0]
	var max_hp := WALLS + float(s.components.instances[reactor]["hp"])
	eq(Structure.totals(s), Vector2(max_hp, max_hp), "walls and the reactor, all whole (floor is no block)")
	eq(Structure.structure_fraction(s), 1.0, "so the structure is 1")
	s.grid.hp[Vector2i(8, 12)] = 1.0  # a wall at 1 of 4
	s.components.instances[reactor]["hp"] = 2.0  # the reactor at 2 of 8
	eq(Structure.totals(s).x, max_hp - 3.0 - 6.0, "current hp is read from the grid and the parts")
	near(Structure.structure_fraction(s), (max_hp - 9.0) / max_hp, "as a fraction")
	s.grid.breach(Vector2i(8, 13))  # a wall shot open counts at 0 of its 4
	eq(Structure.totals(s).y, max_hp, "a breach keeps its maximum")
	eq(Structure.totals(s).x, max_hp - 13.0, "and has no hp")
	s.components.wreck(reactor)  # a wrecked part is debris at 0 of its maximum until it is cleared
	eq(Structure.totals(s).y, max_hp, "wreckage keeps the part's maximum")
	eq(Structure.totals(s).x, max_hp - 3.0 - 4.0 - 8.0, "and counts nothing")


func near(a: float, b: float, msg: String) -> void:
	check(absf(a - b) < 1e-4, "%s: expected %s, got %s" % [msg, str(b), str(a)])


func test_the_fraction_takes_a_combatant_or_a_ship() -> void:
	var s := _ship()
	var a := Arena.new()
	var i := a.add_ship(s)
	StructureUtil.set_structure(s, 0.8)
	near(Structure.structure_fraction(s), 0.8, "a ship")
	near(Structure.structure_fraction(a.ships[i]), 0.8, "an arena combatant")


func test_a_fight_is_lost_below_the_defeat_line() -> void:
	var a := Arena.new()
	var s := _ship()
	var i := a.add_ship(s)
	var line := Structure.defeat_below()
	StructureUtil.set_structure(s, line + 0.02)
	a.step(0.2)
	check(not a.ships[i].wrecked, "2% over the line: still afloat")
	var wall := Vector2i(8, 12)
	s.grid.hp[wall] = 4.0
	Damage.apply(a, i, wall, {"kind": "wall", "def": s.grid.defs.get_def("wall")}, 4.0, "kinetic")  # a breach, and a few points more
	StructureUtil.set_structure(s, line - 0.01)
	a.step(0.1)
	check(a.ships[i].wrecked, "1% under the line: wrecked")
	check(a.events.any(func(e): return e["type"] == "wreck" and e["ship"] == i), "and it says so")


func test_a_hit_on_a_part_counts_too() -> void:
	var a := Arena.new()
	var s := _ship()
	var i := a.add_ship(s)
	StructureUtil.set_structure(s, Structure.defeat_below())  # exactly on the line: not under it
	a.step(0.2)
	check(not a.ships[i].wrecked, "on the line is not under it")
	var uid: int = s.components.instances.keys()[0]
	Damage.apply(a, i, s.components.instances[uid]["cells"][0], {"kind": "component", "uid": uid}, 3.0, "kinetic")
	a.step(0.1)
	check(a.ships[i].wrecked, "3 hp off the reactor takes it under")


func test_fire_wrecks_a_ship_without_a_shot() -> void:
	var a := Arena.new()
	var s := _ship()
	var i := a.add_ship(s)
	StructureUtil.set_structure(s, Structure.defeat_below() - 0.1)  # the structure fell some other way (fire, a ram): the arena looks now and then
	a.step(0.2)
	check(a.ships[i].wrecked, "the arena looks at the structure every few ticks")


func test_nothing_is_carried_between_fights_but_the_damaged_blocks() -> void:
	var c := _campaign()
	var s := _ship()
	StructureUtil.set_structure(s, 0.7)
	var before := Structure.totals(s)
	var r := c.fight_done({"state": "fled"}, s)
	eq(r["state"], "fled", "the fight is over")
	eq(Structure.totals(s), before, "the blocks are as the fight left them: no number was carried, none is applied")
	check(not c.to_dict().has("hull_loss"), "the campaign saves no hull number")
	check(not c.has_method("hull_left") and not c.has_method("fight_hull") and not c.has_method("change_hull"), "and has no hull functions")
	var a := Arena.new()
	a.add_ship(s)
	near(Structure.structure_fraction(a.ships[0]), 0.7, "the next fight begins with the structure it had")


func test_an_old_save_loads_and_its_hull_loss_is_ignored() -> void:
	var c := _campaign(3)
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	d["version"] = 9
	d["hull_loss"] = 40
	var back := _campaign(3)
	eq(back.load_dict(d), "", "a version 9 save with hull_loss loads")
	check(not back.to_dict().has("hull_loss"), "and the number is gone")
	eq(back.to_dict()["version"], Campaign.VERSION, "saved as the current version")
	check(Campaign.VERSION >= 10, "(bumped to 10 or later)")
	var d2: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	eq(_campaign(3).load_dict(d2), "", "a new save has no hull_loss and loads")


func test_the_hull_effect_hurts_outer_blocks_by_the_seeded_choice() -> void:
	var s1 := _ship()
	var s2 := _ship()
	var c1 := _campaign(5)
	var c2 := _campaign(5)
	eq(c1.hurt_blocks(s1, 10), 10, "10 hp dealt")
	eq(c2.hurt_blocks(s2, 10), 10, "10 hp dealt again")
	eq(s1.grid.hp, s2.grid.hp, "the same campaign seed hurts the same blocks")
	eq(WALLS + 8.0 - Structure.totals(s1).x, 10.0, "10 hp off the blocks (184 of walls and the reactor's 8)")
	var cells := s1.grid.hp.keys()
	check(cells.size() >= 4, "spread over several blocks: %d" % cells.size())
	for cell in cells:
		check(cell.x == 8 or cell.x == 22 or cell.y == 8 or cell.y == 17, "an outer wall: " + str(cell))
	var s3 := _ship()
	_campaign(6).hurt_blocks(s3, 10)
	check(s3.grid.hp != s1.grid.hp, "another seed, other blocks")
	eq(c1.mend_blocks(s1, 10), 10, "+10 mends 10 hp")
	eq(Structure.damaged(s1).size(), 0, "and the blocks are whole")
	eq(c1.mend_blocks(s1, 10), 0, "nothing to mend")
	eq(_campaign().hurt_blocks(_ship(), 100000), roundi(Structure.totals(_ship()).x - Structure.defeat_below() * Structure.totals(_ship()).y), "never under the defeat line")


func test_the_station_mends_every_block_for_the_price_per_hp() -> void:
	var c := _campaign()
	var s := _ship()
	s.inventory.counts.erase("credits")
	check(not c.repair(s, "rusthold")["ok"], "sound blocks need nothing")
	s.grid.hp[Vector2i(8, 12)] = 1.0  # 3 hp
	s.grid.breach(Vector2i(9, 8))  # 4 hp
	var uid: int = s.components.instances.keys()[0]
	s.components.instances[uid]["hp"] = 0.0
	s.components.instances[uid]["status"] = "disabled"  # 8 hp
	var each: int = c.price(int(c.cfg["prices"]["repair"]), "clans", s)
	eq(Structure.damaged(s).size(), 3, "three damaged blocks")
	eq(c.repair_cost(s, "rusthold"), 15 * each, "15 hp missing at the price per hp")
	check(not c.repair(s, "rusthold")["ok"], "no credits, no repair")
	eq(Structure.damaged(s).size(), 3, "nothing mended")
	s.inventory.add("credits", 15 * each + 7)
	var r := c.repair(s, "rusthold")
	check(r["ok"], r["text"])
	eq(s.inventory.count("credits"), 7, "paid")
	eq([Structure.damaged(s).size(), Structure.structure_fraction(s), s.components.instances[uid]["status"]], [0, 1.0, "ok"], "every tile and component is whole again")
	eq(s.grid.get_tile(Vector2i(9, 8)), "wall", "the breach is closed")


func test_the_top_bar_has_no_hull_number_and_a_wrench_for_damaged_blocks() -> void:
	var s := _ship()
	var b := BuildMode.new()
	var sim := ShipSim.new()
	sim.ships = [s]
	b.sim = sim
	b.hud = Hud.new()
	b.hud.setup(b)
	var ids := func() -> Array: return b.hud.top_bar.items().map(func(it): return it["id"])
	check(not ids.call().has("hull") and not ids.call().has("wrench"), "a sound ship: no hull figure and no wrench")
	s.grid.hp[Vector2i(8, 12)] = 1.0
	s.grid.breach(Vector2i(9, 8))
	var uid: int = s.components.instances.keys()[0]
	s.components.instances[uid]["hp"] = 3.0
	var items: Array = b.hud.top_bar.items()
	check(not ids.call().has("hull"), "still no hull figure")
	var wrench: Dictionary = items[-1]
	eq([wrench["id"], wrench["text"]], ["wrench", "3 damaged"], "a wrench with the number of damaged blocks")
	eq(wrench["tip"], "Damaged blocks. Crew, drone and F repair them.", "and its hover line")
	for it in items:
		check(not str(it["text"]).contains("/") or it["id"] == "power", "no x/y figure in the bar: " + str(it["text"]))
	b.cam = Camera2D.new()  # a click on the wrench centres the camera on a damaged block
	var bar: Control = b.hud.top_bar
	bar.size = Vector2(1600.0, 36.0)
	var rect: Rect2 = bar.item_rects(items)[-1]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(rect.position.x + 6.0, 10.0)
	bar._gui_input(click)
	check(b._focus_on and b.cam != null, "clicking the wrench starts the camera move")
	click.position = Vector2(8.0, 10.0)  # the first figure is no button
	b._focus_on = false
	bar._gui_input(click)
	check(not b._focus_on, "another figure does nothing")
	b.cam.free()
	b.hud.free()
	sim.free()
	b.free()


func test_the_wrench_centres_the_camera_on_the_nearest_damaged_block_and_then_the_next() -> void:
	var s := _ship()
	var b := BuildMode.new()
	var sim := ShipSim.new()
	sim.ships = [s]
	b.sim = sim
	b.cam = Camera2D.new()
	check(not b.focus_damaged(), "nothing damaged: nothing to centre on")
	var near_cell := Vector2i(9, 8)
	var far_cell := Vector2i(22, 17)
	s.grid.hp[near_cell] = 2.0
	s.grid.hp[far_cell] = 2.0
	b.cam.position = b._origin() + Vector2(near_cell) * 32.0  # looking at the first one
	check(b.focus_damaged(), "a damaged block: the camera goes to it")
	eq(b._focus_cell, near_cell, "the nearest to where the camera looks")
	for i in 120:
		b._follow_focus(1.0 / 60.0)
	var want: Vector2 = b.cell_rect(near_cell).get_center()
	check((b.cam.position + b.cam.offset).distance_to(want) < 2.0, "and the view is centred on that block")
	check(b.focus_damaged(), "pressed again")
	eq(b._focus_cell, far_cell, "it goes on to the next damaged block")
	check(b.focus_damaged(), "and again")
	eq(b._focus_cell, near_cell, "when all have had a turn it starts over")
	b.cam.free()
	sim.free()
	b.free()


func test_the_hull_creak_reads_the_structure_on_the_way_from_whole_to_wrecked() -> void:
	var s := _ship()
	var sim := ShipSim.new()
	sim.ships = [s]
	var audio = Audio.new()
	audio.sim = sim
	near(audio._hull_frac(), 1.0, "a whole ship")
	var line := Structure.defeat_below()
	StructureUtil.set_structure(s, line + 0.5 * (1.0 - line))
	near(audio._hull_frac(), 0.5, "half the way from whole to the wreck line")
	StructureUtil.set_structure(s, line + 0.2 * (1.0 - line))
	near(audio._hull_frac(), 0.2, "a fifth of the way")
	near(Structure.wreck_margin(s), 0.2, "Structure.wreck_margin is what it reads")
	var rules := Ambience.new()  # (set_structure only takes hp off: a fresh ship, then down)
	s = _ship()
	sim.ships = [s]
	StructureUtil.set_structure(s, line + 0.8 * (1.0 - line))
	check(not rules.creak(audio._hull_frac(), 1.0), "90% structure: quiet")
	StructureUtil.set_structure(s, line + 0.4 * (1.0 - line))
	check(rules.creak(audio._hull_frac(), 1.0), "under half the way: one creak")
	check(not rules.creak(audio._hull_frac(), 1.0), "then the cooldown")
	audio.free()
	sim.free()
