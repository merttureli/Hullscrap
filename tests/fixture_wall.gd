extends RefCounted
## Shared by the hull mount tests (not a test: the runner skips it). A 31x31 ship with a flat wall
## `thick` layers deep and floor behind it, facing any of the four ways, in coordinates (u, d):
## u runs along the wall, d is the depth from the outer face: d < 0 is space, 0..thick-1 the wall,
## thick.. the floor. `rot` is the mount's rotation: outward is up at 0, right at 1, down at 2, left at 3.

const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")

const CENTRE := Vector2i(15, 15)


## The grid cell at (u, d) for a wall facing `rot`.
static func at(rot: int, u: int, d: int) -> Vector2i:
	match posmod(rot, 4):
		0:
			return CENTRE + Vector2i(u, d)
		2:
			return CENTRE + Vector2i(u, -d)
		1:
			return CENTRE + Vector2i(-d, u)
	return CENTRE + Vector2i(d, u)


## The top-left grid cell of the rectangle u0..u1, d0..d1 (inclusive).
static func corner(rot: int, u0: int, u1: int, d0: int, d1: int) -> Vector2i:
	var lo := at(rot, u0, d0)
	var hi := lo
	for u in [u0, u1]:
		for d in [d0, d1]:
			lo = lo.min(at(rot, u, d))
			hi = hi.max(at(rot, u, d))
	return lo


## A ship with the wall: steel wall for d in 0..thick-1 and floor for d in thick..thick+5, across u -7..7.
## The cargo holds two of every weapon and engine; `inventory` also has plenty of scrap and copper.
static func wall_ship(thick: int, rot := 0) -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	var ship := Ship.new("Wall", g)
	ship.inventory.load_dict({"scrap": 800, "copper": 40})
	for u in range(-7, 8):
		for d in range(0, thick):
			g.force_tile(at(rot, u, d), "wall")
		for d in range(thick, thick + 6):
			g.force_tile(at(rot, u, d), "floor")
	for id in ship.components.ids():
		if ship.components.is_mount(id):
			ship.inventory.add(id, 2)
	ship.refresh()
	return ship


## Where the outside half goes to be centred on u = -2..1 and sit against the wall (`depth` rows tall).
static func out_anchor(rot: int, depth := 2) -> Vector2i:
	return corner(rot, -2, 1, -depth, -1)
