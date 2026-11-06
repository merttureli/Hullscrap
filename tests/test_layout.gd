extends "res://tests/base_test.gd"
## Save layout and Rebuild (scripts/ship/layout.gd): what is missing or destroyed comes back at the normal cost, hull before
## parts, cargo parts before crafted ones, until the materials run out; one undo step; the layout is saved with the ship.

const BuildSession = preload("res://scripts/ship/build_session.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Layout = preload("res://scripts/ship/layout.gd")
const Ship = preload("res://scripts/ship/ship.gd")

const REACTOR := "reactor_mk1"


## A room ship with a reactor and an oxygen generator on a cable, its layout saved.
func _world() -> Dictionary:
	var ship := Fixture.room_ship()
	Fixture.put(ship, REACTOR, 10, 10)
	Fixture.put(ship, "oxygen_gen", 15, 12)
	Fixture.wire(ship, [Vector2i(14, 12), Vector2i(14, 13)])
	ship.crafting.unlock(REACTOR)
	ship.layout = Layout.capture(ship)
	var s := BuildSession.new(ship)
	return {"ship": ship, "s": s}


func _wreck(ship: Ship) -> void:
	for x in range(9, 15):
		ship.grid.force_tile(Vector2i(x, 16), "")  # six floor cells
	for uid in ship.components.instances.keys():
		ship.components.remove_uid(uid)


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
	eq(ship.components.instances.size(), 0, "hull only: no parts")
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
	eq(ship.components.instances.size(), 2, "two parts stand")
	eq(w["s"].undo_stack.size(), 1, "one undo step")
	check(w["s"].undo(), "undo")
	eq(ship.inventory.counts, cargo, "the cargo is as before, materials included")
	eq(ship.grid.tiles, tiles_before, "tiles as before")
	eq(ship.components.instances.size(), 0, "no parts")
	check(w["s"].redo(), "redo")
	eq(ship.components.instances.size(), 2, "redo puts the parts back")


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
	eq(copy.layout.get("parts", []).size(), 2, "two parts in the layout")
	eq(copy.layout.get("tiles", []).size(), ship.layout["tiles"].size(), "the tiles too")
