extends RefCounted
## Oxygen per room. Each room holds a pressure (0..1, fraction of full); the amount of gas is
## pressure x room size, in cell units. Breached rooms vent, open doors equalise, generators supply
## and crew consume. Pure logic, deterministic: no randomness and no Dictionary-order dependence.
## Air comes from the generators (supply): a working one fills every room reachable from its own through doors, open or
## closed (a door is a blast valve: it gives air out even when closed), evenly among those below full pressure. A breached
## (venting) room is not on the network: its valves shut toward the vacuum, so it takes none and passes none on. A closed
## door never equalises pressure; an open one does, so an open door into a breached room still drains the neighbour.

const Rooms = preload("res://scripts/sim/rooms.gd")
const CONFIG_PATH := "res://data/atmosphere.json"
const MIN_PRESSURE := 0.001  ## a venting room below this is simply empty

var vent_rate := 1.5  ## fraction of pressure a breached room loses per second
var door_rate := 2.0  ## cell units of gas an open door moves per second per unit of pressure difference
var rooms: Array = []  ## from Rooms.compute: {id, cells, size, sealed}
var room_of := {}  ## Vector2i -> room id
var doors: Array = []  ## from Rooms.compute: {cell, a, b}, sorted by cell
var pressure: Array[float] = []  ## per room id


## Pass "" to skip the config file and keep the built-in defaults.
func _init(config_path := CONFIG_PATH) -> void:
	if config_path != "":
		load_config(config_path)


## Read vent_rate and door_rate from a JSON file. Returns false (and keeps the current values) if unusable.
func load_config(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return false
	var v = data.get("vent_rate")
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		vent_rate = maxf(0.0, float(v))
	v = data.get("door_rate")
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		door_rate = maxf(0.0, float(v))
	return true


## Recompute rooms from the grid and carry the oxygen over: a new room gets the average over its
## cells of the pressure those cells had before (cells that are new count as 0.0). A first-ever
## rebuild starts sealed rooms full and open ones empty.
func rebuild(grid) -> void:
	var res := Rooms.compute(grid)
	var fresh := rooms.is_empty()
	var old_room_of := room_of
	var old_pressure := pressure
	var next: Array[float] = []
	for r in res["rooms"]:
		if fresh:
			next.append(1.0 if r["sealed"] else 0.0)
			continue
		var sum := 0.0
		for c in r["cells"]:
			var o: int = old_room_of.get(c, -1)
			if o >= 0:
				sum += old_pressure[o]
		next.append(clampf(sum / r["size"], 0.0, 1.0))
	rooms = res["rooms"]
	room_of = res["room_of"]
	doors = res["doors"]
	pressure = next


## Advance by `dt` seconds. `open_doors` maps door cells to true when open.
## Rooms that are unsealed, or have an open door to space, vent once per tick (one breach or many
## vent the same); open doors between two rooms then move gas toward equal pressure.
func tick(dt: float, open_doors: Dictionary) -> void:
	if dt <= 0.0 or rooms.is_empty():
		return
	var venting := venting_rooms(open_doors)
	var flowing: Array = []  # open doors between two different rooms, in cell order
	for d in doors:
		if not bool(open_doors.get(d["cell"], false)):
			continue
		var a: int = d["a"]
		var b: int = d["b"]
		if a >= 0 and b >= 0 and a != b:
			flowing.append(d)

	var keep := exp(-vent_rate * dt)
	for i in rooms.size():
		if venting[i]:
			pressure[i] *= keep
			if pressure[i] < MIN_PRESSURE:
				pressure[i] = 0.0

	for d in flowing:
		var a: int = d["a"]
		var b: int = d["b"]
		var sa: float = rooms[a]["size"]
		var sb: float = rooms[b]["size"]
		var diff := pressure[a] - pressure[b]
		var flow := diff * door_rate * dt  # cell units from a to b
		var to_equal := diff * sa * sb / (sa + sb)  # moving this much equalises the two
		flow = minf(flow, to_equal) if diff > 0.0 else maxf(flow, to_equal)
		pressure[a] = clampf(pressure[a] - flow / sa, 0.0, 1.0)
		pressure[b] = clampf(pressure[b] + flow / sb, 0.0, 1.0)


## Which rooms are venting now (by room id): the unsealed ones and those with an open door to space.
func venting_rooms(open_doors: Dictionary) -> Array[bool]:
	var out: Array[bool] = []
	for r in rooms:
		out.append(not r["sealed"])
	for d in doors:
		if not bool(open_doors.get(d["cell"], false)):
			continue
		var a: int = d["a"]
		var b: int = d["b"]
		if a >= 0 and b == Rooms.SPACE:
			out[a] = true
		elif b >= 0 and a == Rooms.SPACE:
			out[b] = true
	return out


## The rooms a generator in room `source` supplies (by id, ascending): every room reachable from it through doors, open or
## closed, without entering a venting room (`venting`: venting_rooms()). Empty when `source` itself vents.
func air_network(source: int, venting: Array[bool]) -> Array[int]:
	var out: Array[int] = []
	if source < 0 or source >= rooms.size() or venting[source]:
		return out
	var seen := {source: true}
	var queue: Array[int] = [source]
	while not queue.is_empty():
		var at: int = queue.pop_front()
		out.append(at)
		for d in doors:
			var a: int = d["a"]
			var b: int = d["b"]
			if a < 0 or b < 0 or a == b or (a != at and b != at):
				continue
			var to := b if a == at else a
			if not seen.has(to) and not venting[to]:
				seen[to] = true
				queue.append(to)
	out.sort()
	return out


## A generator in room `source` puts `amount` cell units of oxygen into its air network (air_network), evenly: every room
## below full pressure gains the same pressure, rooms that fill up leaving the rest to the others. Returns what was added.
## Nothing happens (0.0) when the generator's own room is breached.
func supply(source: int, amount: float, open_doors: Dictionary) -> float:
	if amount <= 0.0:
		return 0.0
	var open: Array[int] = air_network(source, venting_rooms(open_doors)).filter(func(r): return pressure[r] < 1.0)
	var left := amount
	while left > 1.0e-12 and not open.is_empty():
		var total := 0.0
		var least := INF
		for r in open:
			total += float(rooms[r]["size"])
			least = minf(least, 1.0 - pressure[r])
		var step := minf(left / total, least)
		for r in open:
			pressure[r] = 1.0 if 1.0 - pressure[r] - step < 1.0e-9 else pressure[r] + step
		left -= step * total
		open = open.filter(func(r): return pressure[r] < 1.0)
	return amount - maxf(left, 0.0)


## Add `amount` cell units of oxygen to a room (a spore aura, a test). Returns what was actually added.
func add_oxygen(room_id: int, amount: float) -> float:
	return _change(room_id, amount)


## Take `amount` cell units of oxygen from a room (crew). Returns what was actually taken.
func consume(room_id: int, amount: float) -> float:
	return -_change(room_id, -amount)


func pressure_at(cell: Vector2i) -> float:
	return pressure_of(room_of.get(cell, -1))


## Pressure of a room, 0.0 for an unknown id.
func pressure_of(room_id: int) -> float:
	return pressure[room_id] if room_id >= 0 and room_id < pressure.size() else 0.0


## Id of the room holding `cell`, or -1.
func room_at(cell: Vector2i) -> int:
	return room_of.get(cell, -1)


## Gas in a room in cell units (pressure x size).
func oxygen_of(room_id: int) -> float:
	if room_id < 0 or room_id >= pressure.size():
		return 0.0
	return pressure[room_id] * rooms[room_id]["size"]


func total_oxygen() -> float:
	var sum := 0.0
	for i in rooms.size():
		sum += oxygen_of(i)
	return sum


## Move a room's gas by `amount` cell units, clamped to 0..1 pressure; returns the signed change.
func _change(room_id: int, amount: float) -> float:
	if room_id < 0 or room_id >= pressure.size():
		return 0.0
	var size: float = rooms[room_id]["size"]
	var before := pressure[room_id]
	pressure[room_id] = clampf(before + amount / size, 0.0, 1.0)
	return (pressure[room_id] - before) * size
