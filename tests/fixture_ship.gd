extends RefCounted
## Shared by the lines, heat, reliability and visuals tests (not a test: the runner skips it).
## A 31x31 ship with one sealed, floored room (floor x 9..21, y 9..16) and helpers to fill it.

const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")


static func room_ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	var ship := Ship.new("Test", g)
	ship.inventory.load_dict({"scrap": 800, "copper": 40})
	BuildSession.new(ship).apply(BuildSession.room_changes(Vector2i(8, 8), Vector2i(22, 17), "wall", "floor"))
	ship.refresh()
	return ship


## Place `id` with its top-left cell at x, y; returns the uid (-1 when it does not fit).
static func put(ship: Ship, id: String, x: int, y: int, rot := 0) -> int:
	return ship.components.place(ship.grid, id, Vector2i(x, y), rot)


## Cables on the given cells.
static func wire(ship: Ship, cells: Array) -> void:
	for c in cells:
		ship.cables.place(ship.grid, c)
