extends "res://tests/base_test.gd"
## Save layout and Rebuild (scripts/ship/layout.gd): what is missing or destroyed comes back at the normal cost, hull before
## parts, cargo parts before crafted ones, until the materials run out; one undo step; the layout is saved with the ship.

const BuildSession = preload("res://scripts/ship/build_session.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Layout = preload("res://scripts/ship/layout.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")
const LayoutBar = preload("res://scripts/ui/layout_bar.gd")

const REACTOR := "reactor_mk1"


class BuildStub:
	extends RefCounted
	var ship


class HudStub:
	extends Control
	var build


## A room ship with a reactor and an oxygen generator on a cable, its layout saved.
func _world() -> Dictionary:
	var ship := Fixture.room_ship()
	Fixture.put(ship, REACTOR, 10, 10)
	Fixture.put(ship, "oxygen_gen", 15, 12)
	Fixture.wire(ship, [Vector2i(14, 12), Vector2i(14, 13)])
	ship.crafting.unlock(REACTOR)
	w_fab(ship)
	ship.layout = Layout.capture(ship)
	var s := BuildSession.new(ship)
	return {"ship": ship, "s": s}


## A fabricator (level 1) on its own spare reactor: it survives _wreck, so parts can be made on the spot.
func w_fab(ship: Ship) -> int:
	Fixture.put(ship, REACTOR, 19, 12)
	var fab := Fixture.put(ship, "fabricator", 15, 10)
	Fixture.wire(ship, [Vector2i(18, 11), Vector2i(19, 11), Vector2i(19, 12)])
	ship.refresh()
	return fab


func _wreck(ship: Ship) -> void:
	for x in range(9, 15):
		ship.grid.force_tile(Vector2i(x, 16), "")  # six floor cells
	for uid in ship.components.instances.keys():
		if ship.components.instances[uid]["id"] == "oxygen_gen" or Vector2i(ship.components.instances[uid]["anchor"]) == Vector2i(10, 10):
			ship.components.remove_uid(uid)
	ship.refresh()


func _mats(id: String, ship: Ship) -> Dictionary:
	return ship.crafting.def(id).get("materials", {})


func test_hull_restores_tiles_only() -> void:
	var w := _world()
	var ship: Ship = w["ship"]
	var tiles: Dictionary = ship.grid.tiles.duplicate()
	_wreck(ship)
	var r := Layout.rebuild(w["s"], ship.layout, "hull")
	eq(ship.grid.tiles, tiles, "every tile is back")
	eq(r["hull_done"], 6, "six cells rebuilt")
	eq(ship.components.instances.size(), 2, "hull only: no parts (the spare reactor and fabricator stayed)")
	check(r["text"].begins_with("Rebuilt 6 hull cells"), "summary: " + r["text"])


func test_parts_come_from_the_cargo_first() -> void:
	var w := _world()
	var ship: Ship = w["ship"]
	_wreck(ship)
	ship.inventory.add(REACTOR, 1)
	var scrap := ship.inventory.count("scrap")
	var r := Layout.rebuild(w["s"], ship.layout, "parts")
	eq(ship.inventory.count(REACTOR), 0, "the cargo reactor is placed")
	eq(r["parts_done"], 2, "both parts back")
	check(scrap - ship.inventory.count("scrap") > 0 and ship.inventory.count(REACTOR) == 0, "the generator was made (paid)")


func test_both_and_undo() -> void:
	var w := _world()
	var ship: Ship = w["ship"]
	_wreck(ship)
	var cargo := ship.inventory.counts.duplicate()
	var tiles_before: Dictionary = ship.grid.tiles.duplicate()
	var r := Layout.rebuild(w["s"], ship.layout, "both")
	eq(r["parts_done"], 2, "parts crafted on the spot")
	eq(ship.components.instances.size(), 4, "two parts stand")
	eq(w["s"].undo_stack.size(), 1, "one undo step")
	check(w["s"].undo(), "undo")
	eq(ship.inventory.counts, cargo, "the cargo is as before, materials included")
	eq(ship.grid.tiles, tiles_before, "tiles as before")
	eq(ship.components.instances.size(), 2, "no parts")
	check(w["s"].redo(), "redo")
	eq(ship.components.instances.size(), 4, "redo puts the parts back")


func test_stops_when_materials_run_out() -> void:
	var w := _world()
	var ship: Ship = w["ship"]
	_wreck(ship)
	ship.inventory.load_dict({"scrap": 3})
	var r := Layout.rebuild(w["s"], ship.layout, "both")
	check(r["hull_done"] < 6 or r["parts_done"] < 2, "not everything fits")
	check(not r["short"].is_empty(), "something is short")
	check(r["text"].contains("Short:"), "the summary says what: " + r["text"])
	check(ship.inventory.count("scrap") >= 0, "never overspends")


func test_unknown_blueprint_is_listed() -> void:
	var w := _world()
	var ship: Ship = w["ship"]
	_wreck(ship)
	ship.crafting.known.erase(REACTOR)
	var r := Layout.rebuild(w["s"], ship.layout, "parts")
	eq(r["parts_done"], 1, "the generator only")
	check(r["text"].contains("blueprint not known"), "listed: " + r["text"])


func test_layout_is_saved_with_the_ship() -> void:
	var w := _world()
	var ship: Ship = w["ship"]
	var d := ship.to_dict()
	var copy := Fixture.room_ship()
	eq(copy.load_dict(JSON.parse_string(JSON.stringify(d))), "", "loads")
	eq(copy.layout.get("parts", []).size(), 4, "four parts in the layout")
	eq(copy.layout.get("tiles", []).size(), ship.layout["tiles"].size(), "the tiles too")


## A level 3 part (reactor_mk2) added to the layout, with its materials aboard.
func _mk2(w: Dictionary) -> void:
	var ship: Ship = w["ship"]
	ship.crafting.unlock("reactor_mk2")
	ship.inventory.add("titanium", 20)
	ship.inventory.add("silicon", 10)
	ship.inventory.add("plasma_cell", 4)
	ship.layout["parts"].append({"id": "reactor_mk2", "anchor": [12, 13], "rot": 0})


func test_a_level_3_part_needs_a_level_3_fabricator() -> void:
	var w := _world()
	var ship: Ship = w["ship"]
	_mk2(w)
	var r := Layout.rebuild(w["s"], ship.layout, "parts")
	eq(r["parts_done"], 0, "not made at level 1")
	check(r["text"].contains("needs fabricator level 3"), "listed: " + r["text"])
	eq(ship.components.any_at(Vector2i(12, 13)), -1, "nothing stands there")


func test_a_level_3_part_is_made_at_level_3() -> void:
	var w := _world()
	var ship: Ship = w["ship"]
	_mk2(w)
	ship.components.instances[Workshop.fab_uid(ship)]["fab_level"] = 3
	var r := Layout.rebuild(w["s"], ship.layout, "parts")
	eq(r["parts_done"], 1, "made")
	check(ship.components.any_at(Vector2i(12, 13)) >= 0, "it stands: " + r["text"])


func test_no_working_fabricator_makes_nothing() -> void:
	var w := _world()
	var ship: Ship = w["ship"]
	_wreck(ship)
	ship.components.remove_uid(Workshop.fab_uid(ship))
	ship.refresh()
	ship.inventory.add(REACTOR, 1)
	var r := Layout.rebuild(w["s"], ship.layout, "parts")
	check(r["text"].contains("needs a working fabricator"), "the generator is listed: " + r["text"])
	eq(ship.inventory.count(REACTOR), 0, "but the cargo reactor is placed with no fabricator")


func test_belts_round_trip_and_rebuild() -> void:
	var w := _world()
	var ship: Ship = w["ship"]
	ship.belts.known = true
	for x in range(10, 13):
		check(ship.belts.place(ship.grid, ship.components, Vector2i(x, 15)), "belt laid")
	ship.layout = Layout.capture(ship)
	eq(ship.layout["belts"].size(), 3, "three belts saved")
	var copy := Fixture.room_ship()
	eq(copy.load_dict(JSON.parse_string(JSON.stringify(ship.to_dict()))), "", "loads")
	eq(copy.layout["belts"].size(), 3, "saved with the ship")
	for x in range(10, 13):
		ship.belts.remove(Vector2i(x, 15))
	var r := Layout.rebuild(w["s"], ship.layout, "parts")
	eq(ship.belts.cells.size(), 3, "belts are back")
	check(r["text"].contains("Belts: 3 of 3"), r["text"])
	ship.belts.known = false
	for x in range(10, 13):
		ship.belts.remove(Vector2i(x, 15))
	r = Layout.rebuild(w["s"], ship.layout, "parts")
	eq(ship.belts.cells.size(), 0, "locked: none laid")
	check(r["text"].contains("Not built:") and r["text"].contains("belt drive"), "listed once: " + r["text"])


func test_nothing_missing() -> void:
	var w := _world()
	var r := Layout.rebuild(w["s"], w["ship"].layout, "both")
	eq(r["text"], "Nothing missing.", "says so")


func test_the_bar_is_dimmed_without_a_layout() -> void:
	var bar := LayoutBar.new()
	bar.size = Vector2(300, 80)
	check(bar.has_layout(), "no HUD yet: not dimmed")
	var ship := Fixture.room_ship()
	var b := BuildStub.new()
	b.ship = ship
	bar.hud = HudStub.new()
	bar.hud.build = b
	check(not bar.has_layout(), "nothing saved: dimmed")
	eq(bar._get_tooltip(bar.button_rect(2).get_center()), "Save a layout first", "the tooltip")
	eq(bar._get_tooltip(bar.button_rect(0).get_center()), "", "Save layout has none")
	ship.layout = Layout.capture(ship)
	check(bar.has_layout(), "saved: lit")
	eq(bar._get_tooltip(bar.button_rect(2).get_center()), "", "no tooltip then")
	bar.hud.free()
	bar.free()
