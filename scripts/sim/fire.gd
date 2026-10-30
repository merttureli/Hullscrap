extends RefCounted
## Fires (docs/CONTENT.md sections 2-4). A fire burns on one floor cell (a cell under a part counts)
## with an intensity from 0 to 1, kept in `ship.fires` (cell -> intensity, saved with the ship).
## Per second: while the room's air is above MIN_AIR the intensity grows by GROW, below it the fire
## decays by DECAY and goes out at 0; each burning cell has a SPREAD chance to light a random
## neighbouring floor cell and uses AIR_USE of the room's oxygen; a part standing on a burning cell
## loses PART_DAMAGE hp (at 0 it is disabled). Crew put fires out (jobs.gd, `extinguish`) and
## standing in one hurts (jobs.gd). Doors and walls are not floor, so a fire stays in its room.
## Deterministic: the spread rolls come from the rng the caller passes (ShipSim's), cells are
## visited in (y, x) order.

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const GROW := 0.15  ## intensity gained per second while the air is good
const DECAY := 0.3  ## intensity lost per second while it is not
const MIN_AIR := 0.2  ## room pressure: fires grow above it and die below it
const SPREAD := 0.1  ## chance per second that a burning cell lights a neighbour
const AIR_USE := 0.05  ## oxygen (cell units) a burning cell uses per second
const PART_DAMAGE := 0.5  ## hp per second a part on a burning cell loses
const START := 0.2  ## intensity of a new fire
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


## Can a fire burn on `c`? A tile that is neither a wall nor a door.
static func is_floor(ship, c: Vector2i) -> bool:
	var id: String = ship.grid.get_tile(c)
	return id != "" and not ship.grid.tile_flag(id, "solid") and not ship.grid.tile_flag(id, "door")


## Light a fire on floor cell `c` (a burning cell stays as strong as it is, at least `intensity`).
## Logs "Fire in <room>" when the room had no fire. False when `c` is not floor.
static func ignite(ship, c: Vector2i, intensity := START) -> bool:
	if not is_floor(ship, c):
		return false
	var room: int = ship.atmosphere.room_at(c)
	var first := not _burning_in(ship, room)
	ship.fires[c] = clampf(maxf(float(ship.fires.get(c, 0.0)), intensity), 0.0, 1.0)
	if first:
		ship.log_event("Fire in " + room_name(ship, room))
	return true


## Light a fire where something hit cell `c`: on `c` when it is floor (or a part), else on the first
## floor cell beside it (a wall was hit). False when there is none.
static func ignite_near(ship, c: Vector2i) -> bool:
	if ignite(ship, c):
		return true
	for d in SIDES:
		if ignite(ship, c + d):
			return true
	return false


## Light a fire on the first cell of part `uid` (a part overheated or malfunctioned).
static func ignite_part(ship, uid: int) -> bool:
	if not ship.components.instances.has(uid):
		return false
	return ignite(ship, ship.components.instances[uid]["cells"][0])


## Put the fire on `c` out. Logs "Fire out" when it was the last one in its room.
static func extinguish(ship, c: Vector2i) -> void:
	if not ship.fires.has(c):
		return
	ship.fires.erase(c)
	var room: int = ship.atmosphere.room_at(c)
	if not _burning_in(ship, room):
		ship.log_event("Fire out")


## Advance every fire of `ship` by `dt` seconds. `rng`: for the spread rolls; null means no spreading.
static func tick(ship, dt: float, rng: RandomNumberGenerator = null) -> void:
	if dt <= 0.0 or ship.fires.is_empty():
		return
	ship.refresh()
	var atmo = ship.atmosphere
	var out: Array[Vector2i] = []
	var lit: Array[Vector2i] = []
	var parts := {}
	for c in sorted_cells(ship.fires.keys()):
		if not is_floor(ship, c):
			out.append(c)  # the floor was shot away
			continue
		var room: int = atmo.room_at(c)
		var air: float = atmo.pressure_of(room)
		var i: float = ship.fires[c]
		if air > MIN_AIR:
			i = minf(i + GROW * dt, 1.0)
		elif air < MIN_AIR:
			i -= DECAY * dt
		ship.fires[c] = i
		if i <= 0.0:
			out.append(c)
			continue
		atmo.consume(room, AIR_USE * dt)
		var uid: int = ship.components.at(c)
		if uid >= 0:
			parts[uid] = true
		if rng != null and rng.randf() < SPREAD * dt:
			var open: Array[Vector2i] = []
			for d in SIDES:
				if is_floor(ship, c + d):
					open.append(c + d)
			if not open.is_empty():
				lit.append(open[rng.randi() % open.size()])
	for c in out:
		extinguish(ship, c)
	for c in lit:
		if not ship.fires.has(c):
			ignite(ship, c)
	var uids: Array = parts.keys()
	uids.sort()
	for uid in uids:
		_burn_part(ship, ship.components.instances[uid], dt)


## Is any cell of room `room_id` on fire? (Any fire at all for a cell that is in no room.)
static func _burning_in(ship, room_id: int) -> bool:
	if room_id < 0:
		return not ship.fires.is_empty()
	for c in ship.fires:
		if ship.atmosphere.room_at(c) == room_id:
			return true
	return false


## The fire eats the part's hp; at 0 it is disabled (until crew repair it).
static func _burn_part(ship, inst: Dictionary, dt: float) -> void:
	inst["hp"] = maxf(float(inst["hp"]) - PART_DAMAGE * dt, 0.0)
	if inst["hp"] <= 0.0 and inst["status"] != "disabled":
		inst["status"] = "disabled"
		ship.log_event("%s is disabled" % ship.components.def(inst["id"]).get("name", inst["id"]))


## What the chronicle calls room `room_id`: by the first part family found in it (data/crew.json).
static func room_name(ship, room_id: int) -> String:
	var cfg := CrewMember.config()
	var here := {}
	for uid in ship.components.instances:
		var inst: Dictionary = ship.components.instances[uid]
		if ship.atmosphere.room_at(inst["anchor"]) == room_id:
			here[str(ship.components.def(inst["id"]).get("family", ""))] = true
	for pair in cfg.get("room_names", []):
		if here.has(pair[0]):
			return str(pair[1])
	return str(cfg.get("room_default", "room"))


## Cells in (y, x) order.
static func sorted_cells(cells: Array) -> Array:
	cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return cells
