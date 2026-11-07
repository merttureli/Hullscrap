extends RefCounted
## Abandoned rooms and walking out of bad air (playtest 2, K2 and K3). Static functions over a Ship: no nodes.
## - abandon() gives a room up: `ship.abandoned` holds the key cell of each such room (Rooms.key_of: ids shift when the ship
##   is rebuilt, the smallest cell of a room does not), sync() marks the rooms (rooms[i]["abandoned"]) and locks their doors
##   (grid.door_locked: Pathfinder keeps crew out unless the caller passes its own door_passable, as the soldier's moves do),
##   and every crew member in it walks out to the nearest room with air. Jobs.build_board takes the room's jobs off the board.
##   reopen() takes the room back. The list is saved with the ship ("abandoned").
## - path_out() is the walk itself: the shortest way to a spot whose room has air (crew.json air.breath_ok) and is not abandoned.
##   Jobs uses it for K3 too: a hurt crew member leaves an airless room.

const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Rooms = preload("res://scripts/sim/rooms.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")

const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const MAX_SEARCH := 8000  ## anchors a walk-out search may visit


## Is room `room_id` abandoned?
static func is_abandoned(ship, room_id: int) -> bool:
	return room_id >= 0 and room_id < ship.atmosphere.rooms.size() and bool(ship.atmosphere.rooms[room_id].get("abandoned", false))


## The ids of the abandoned rooms.
static func rooms(ship) -> Array:
	var out := []
	for r in ship.atmosphere.rooms:
		if bool(r.get("abandoned", false)):
			out.append(int(r["id"]))
	return out


## Give up room `room_id`: no jobs in it, crew walk out, its doors lock. Returns the names of the crew who walk out.
## The soldier is the player's own: they stay where they are and may walk in and out. Does nothing for an unknown room.
static func abandon(ship, room_id: int) -> Array:
	var out := []
	if room_id < 0 or room_id >= ship.atmosphere.rooms.size():
		return out
	var key := Rooms.key_of(ship.atmosphere.rooms[room_id])
	if not ship.abandoned.has(key):
		ship.abandoned.append(key)
	ship.atmosphere.rooms[room_id]["abandoned"] = true  # (before the walk: a room to walk to is not this one)
	for m in ship.crew:
		if m.is_player or ship.atmosphere.room_at(m.cell()) != room_id:
			continue
		m.job = {}
		m.path.clear()
		var p := path_out(ship, m)
		if not p.is_empty():
			m.path.assign(p)
			m.hold = float(p.size()) / maxf(m.speed * m.speed_mod, 0.1) + 1.0  # the board leaves them alone until they are out
		out.append(m.name)
	sync(ship)
	return out


## Take room `room_id` back: its doors unlock and the board gives it jobs again. False when it was not abandoned.
static func reopen(ship, room_id: int) -> bool:
	if not is_abandoned(ship, room_id):
		return false
	var key := Rooms.key_of(ship.atmosphere.rooms[room_id])
	ship.abandoned.erase(key)
	ship.atmosphere.rooms[room_id]["abandoned"] = false
	sync(ship)
	return true


## Bring the marks up to date with `ship.abandoned`: the rooms' flags and the locked doors. Keys of rooms that are gone are dropped.
## Ship.refresh calls it after the rooms are rebuilt, and Jobs every time it builds the board.
static func sync(ship) -> void:
	var g = ship.grid
	g.door_locked.clear()
	var at = ship.atmosphere
	for r in at.rooms:
		r["abandoned"] = false
	var keep: Array = []
	for key in ship.abandoned:
		var id: int = at.room_at(key)
		if id >= 0 and not keep.has(Rooms.key_of(at.rooms[id])):
			at.rooms[id]["abandoned"] = true
			keep.append(Rooms.key_of(at.rooms[id]))
	ship.abandoned.assign(keep)
	if keep.is_empty():
		return
	for d in at.doors:
		if is_abandoned(ship, int(d["a"])) or is_abandoned(ship, int(d["b"])):
			for p in g.door_piece(d["cell"]):
				g.door_locked[p] = true
				g.door_open.erase(p)  # shut


## Is room `room_id` lost in the fight on now (see lost_rooms; Jobs.build_board keeps `ship.lost_rooms` up to date)?
static func is_lost(ship, room_id: int) -> bool:
	return room_id >= 0 and ship.lost_rooms.has(room_id)


## The ids of the rooms that are lost: the cells of a room's boundary (the walls and doors round it, shot-open ones included) that are
## shot open number at least max(crew.json lost.min_open, lost.share of the boundary cells). Only a fight loses rooms (Jobs asks only then).
static func lost_rooms(ship) -> Array:
	var cfg: Dictionary = CrewMember.config().get("lost", {})
	var out := []
	for o in openings(ship):
		if o["open"] > 0 and o["open"] >= maxi(int(cfg.get("min_open", 3)), ceili(float(cfg.get("share", 0.2)) * o["edge"] - 1e-6)):
			out.append(o["id"])
	return out


## For each room with a boundary cell shot open: {id, key (Rooms.key_of), open (boundary cells shot open), edge (boundary cells: the walls and doors round the
## room, the shot-open ones included)}. A shot-open cell of a thick wall counts only where it touches the room.
static func openings(ship) -> Array:
	var grid = ship.grid
	var out := []
	if grid.breached.is_empty():
		return out
	for r in ship.atmosphere.rooms:
		var edge := {}
		var open := 0
		for c in r["cells"]:
			for d in SIDES:
				var n: Vector2i = c + d
				if edge.has(n) or ship.atmosphere.room_at(n) == int(r["id"]):
					continue
				if grid.breached.has(n):
					edge[n] = true
					open += 1
				elif grid.tile_flag(grid.get_tile(n), "solid") or grid.tile_flag(grid.get_tile(n), "door"):
					edge[n] = true
		if open > 0:
			out.append({"id": int(r["id"]), "key": Rooms.key_of(r), "open": open, "edge": edge.size()})
	return out


## The cells of the abandoned rooms: cell -> true.
static func cells(ship) -> Dictionary:
	var out := {}
	for id in rooms(ship):
		for c in ship.atmosphere.rooms[id]["cells"]:
			out[c] = true
	return out


## The room a body standing with its top-left cell on `anchor` breathes in (the one under its centre), -1 for none.
static func room_at_anchor(ship, anchor: Vector2i, body: int) -> int:
	var c := Pathfinder.centre_of(anchor, body)
	return ship.atmosphere.room_at(Vector2i(floori(c.x), floori(c.y)))


## The shortest walk for `m` to a spot whose room has air (pressure of at least air.breath_ok) and is not abandoned: body
## anchors from where they stand, [] when there is none or they are there already. Locked doors stop the walk, so call it
## before a room is locked behind a crew member.
static func path_out(ship, m, from := Pathfinder.NO_CELL) -> Array[Vector2i]:
	var ok := float(CrewMember.config().get("air", {}).get("breath_ok", 0.5))
	var at = ship.atmosphere
	return path_to(ship, m, func(a: Vector2i) -> bool:
		var r := room_at_anchor(ship, a, m.body_size)
		return r >= 0 and at.pressure_of(r) >= ok and not is_abandoned(ship, r) and not is_lost(ship, r), from)


## The shortest walk for `m` to the nearest body anchor `accept` says yes to (a breadth-first search over the anchors a body
## fits on): the path including the first anchor, or [] when none is found, they are already at one, or no anchor fits.
## `from`: start at that body anchor instead of where `m` stands.
static func path_to(ship, m, accept: Callable, from := Pathfinder.NO_CELL) -> Array[Vector2i]:
	var grid = ship.grid
	var out: Array[Vector2i] = []
	var start := from if from != Pathfinder.NO_CELL else Pathfinder.nearest_walkable(grid, m.pos, Callable(), Pathfinder.NO_CELL, m.body_size)
	if start == Pathfinder.NO_CELL or accept.call(start):
		return out
	var came := {start: start}
	var memo := {}  # (Pathfinder.body_ok_memo: each cell asked once)
	var queue: Array[Vector2i] = [start]
	var i := 0
	while i < queue.size() and i < MAX_SEARCH:
		var a: Vector2i = queue[i]
		i += 1
		for d in SIDES:
			var n: Vector2i = a + d
			if came.has(n) or not Pathfinder.body_ok_memo(grid, n, memo, Callable(), m.body_size):
				continue
			came[n] = a
			if accept.call(n):
				var at := n
				while at != start:
					out.push_front(at)
					at = came[at]
				out.push_front(start)
				return out
			queue.append(n)
	return out
