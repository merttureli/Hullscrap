extends RefCounted
## Shared by the ammo and belt tests (not a test: the runner skips it). Ships on the wall fixture (fixture_wall.gd, rot 0:
## the wall is row y 15, floor is x 8..22 by y 16..21) with a gun mounted through the wall, a reactor and cables.

const Wall = preload("res://tests/fixture_wall.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Arena = preload("res://scripts/combat/arena.gd")

const AIM := Vector2(0.0, -1000.0)  ## the world point fixed guns are aimed at (straight up, along the guns)


## One room: the gun `gun_id` (inside half x 13..16, y 16..17), a reactor at (19, 16) and the cables joining them.
## Returns {ship, gun, reactor}.
static func room(gun_id := "artemis_mk1") -> Dictionary:
	var ship := Wall.wall_ship(1, 0)
	var gun: int = ship.components.place_mount(ship.grid, gun_id, Wall.out_anchor(0), 0)
	var reactor: int = ship.components.place(ship.grid, "reactor_mk1", Vector2i(19, 16), 0)
	for c in [Vector2i(16, 17), Vector2i(17, 17), Vector2i(18, 17), Vector2i(19, 17)]:
		ship.cables.place(ship.grid, c)
	ship.refresh()
	return {"ship": ship, "gun": gun, "reactor": reactor}


## `room()` plus a rack in the gun's room (at (20, 20)); returns it with `rack`.
static func with_rack(gun_id := "artemis_mk1") -> Dictionary:
	var d := room(gun_id)
	d["rack"] = d["ship"].components.place(d["ship"].grid, "ammo_rack", Vector2i(20, 20), 0)
	d["ship"].refresh()
	return d


## The belt rig: a wall column at x 12 (with a 2-cell door at y 18..19) splits the floor in a west room, holding the rack
## (cells x 9..10, y 18..19), and an east room with the gun. A belt runs along y 18 from the rack through the door to x 17;
## drive `drive_id` sits at (14, 19) (touching the belt at x 14..15) and, with `two_drives`, a second at (16, 19). All wired to
## the reactor. Returns {ship, gun, reactor, rack, drive, drive2, belt (the cells)}.
static func belts(gun_id := "artemis_mk1", drive_id := "belt_drive_std", two_drives := false) -> Dictionary:
	var d := room(gun_id)
	var ship: Ship = d["ship"]
	for y in range(16, 22):
		ship.grid.force_tile(Vector2i(12, y), "wall")
	ship.grid.place_door("door", Vector2i(12, 18), Vector2i.DOWN)
	d["rack"] = ship.components.place(ship.grid, "ammo_rack", Vector2i(9, 18), 0)
	d["drive"] = ship.components.place(ship.grid, drive_id, Vector2i(14, 19), 0)
	d["drive2"] = ship.components.place(ship.grid, drive_id, Vector2i(16, 19), 0) if two_drives else -1
	var cells: Array[Vector2i] = []
	for x in range(11, 18):
		cells.append(Vector2i(x, 18))
		ship.belts.cells[Vector2i(x, 18)] = true
	ship.belts.rev += 1
	d["belt"] = cells
	for x in range(15, 20):
		ship.cables.place(ship.grid, Vector2i(x, 19))
	ship.mark_dirty()  # the walls and the door were forced in: the rooms are new
	ship.refresh()
	return d


## A fight arena with just `ship`; returns it (the ship is index 0).
static func arena(ship: Ship) -> Arena:
	var a := Arena.new(1)
	a.add_ship(ship)
	return a


## Fill rack `uid` of `ship` with `n` units of `item`.
static func stock(ship: Ship, uid: int, item: String, n: int) -> void:
	ship.components.instances[uid]["ammo"] = item
	ship.components.instances[uid]["n"] = n
