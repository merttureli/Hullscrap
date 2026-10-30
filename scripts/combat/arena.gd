extends RefCounted
## The 1v1 combat world, headless: two or more ships, each with a flight body, its grid, shield
## state, weapon cooldowns and hull integrity, plus the shots in flight. step() advances in fixed
## substeps of 1/60 s, so the same seed and inputs replay exactly. No nodes, no drawing, no input.
##
## Coordinates: world is pixels; a ship's pivot (the centre of its hull's bounding box) sits at its
## flight body's `pos`, and its grid turns by the body's `angle` (0 faces up, positive is clockwise
## on screen, as in flight.gd). A cell is 32 px.

const Flight = preload("res://scripts/sim/flight.gd")
const Power = preload("res://scripts/sim/power.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Projectiles = preload("res://scripts/combat/projectiles.gd")
const Shields = preload("res://scripts/combat/shields.gd")

const SUBSTEP := 1.0 / 60.0
const CELL := 32.0  ## pixels per grid cell
const HULL_BASE := 20.0  ## hull integrity of a ship with no armour
const HULL_PER_ARMOR := 2.0  ## per wall cell whose material is not plain steel

## One ship in the arena.
class Combatant extends RefCounted:
	var ship  ## ship.gd instance (grid, components, cables)
	var flight  ## flight.gd body: pos, vel, angle, ang_vel
	var pivot := Vector2.ZERO  ## the ship's centre in grid cell coordinates
	var half := Vector2.ZERO  ## half the hull's bounding box, in cells
	var hull_max := HULL_BASE
	var hull := HULL_BASE
	var wrecked := false  ## hull at 0: no firing, no shields, no thrust; stays in the arena
	var mounts := {}  ## uid -> {id, pos (cell coordinates), virtual, powered (virtual only)}
	var cooldowns := {}  ## uid -> arena tick when the mount may fire again
	var powered := {}  ## uid -> bool, the power solve with disabled parts left out
	var mass := 1.0
	var thrust := 0.0
	var layers := 0  ## shield layers up now
	var layers_cap := 0
	var shield_timers: Array[float] = []  ## seconds until each used layer is back
	var ion_lock := 0.0  ## seconds the shields stay offline
	var input := {"throttle": 0.0, "turn": 0.0}
	var dirty := true  ## parts or tiles changed: power, mass and shield cap need recomputing
	var next_virtual := -1

var ships: Array = []  ## Combatant objects; the index is the ship's id everywhere
var rng := RandomNumberGenerator.new()
var weapons := Weapons.new()
var projectiles: Array = []
var beams: Array = []
var events: Array = []  ## {tick, type, ship, cell, ...}: shot, shield, ion_lock, hit, deflect, ricochet, breach, disable, ignite (a hit started a fire), wreck
var power_bonus := {}  ## ship index -> power the neon lattice has made of absorbed energy (counted, not used yet)
var tick := 0  ## substeps run so far
var _acc := 0.0


func _init(seed_value := 1) -> void:
	rng.seed = seed_value


## Seconds of simulated time.
func time() -> float:
	return tick * SUBSTEP


## Put `ship` into the arena at `pos`, turned by `angle`. Returns its index. Its weapon
## components become mounts; the hull integrity, shield layers and flight masses are set up here.
func add_ship(ship, pos := Vector2.ZERO, angle := 0.0) -> int:
	var co := Combatant.new()
	co.ship = ship
	co.flight = Flight.new()
	co.flight.pos = pos
	co.flight.angle = angle
	var grid = ship.grid
	if grid.defs != null:  # the tile masses of data/tiles.json (flight.json knows only the old three)
		for id in grid.defs.ids():
			if grid.defs.get_def(id).has("mass"):
				co.flight.tile_mass[id] = float(grid.defs.get_def(id)["mass"])
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in grid.hull:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x + 1.0), maxf(hi.y, c.y + 1.0))
	if grid.hull.is_empty():
		lo = Vector2(grid.size) / 2.0
		hi = lo
	co.pivot = (lo + hi) / 2.0
	co.half = (hi - lo) / 2.0
	var armor := 0
	for c in grid.tiles:
		if grid.tiles[c] != "wall" and grid.tile_flag(grid.tiles[c], "solid"):
			armor += 1
	co.hull_max = HULL_BASE + HULL_PER_ARMOR * armor
	co.hull = co.hull_max
	co.mounts = weapons.mounts_of(ship)
	ships.append(co)
	_recompute(co)
	co.layers = co.layers_cap  # shields start full
	return ships.size() - 1


## Give ship `idx` a weapon by id without a placed component (the test_* weapons, or any entry of
## weapons.json). `cell_pos` is where it sits, in grid cell coordinates. Returns its mount uid
## (negative, so it never clashes with a component uid).
func add_mount(idx: int, weapon_id: String, cell_pos: Vector2, powered := true) -> int:
	var co = ships[idx]
	var uid: int = co.next_virtual
	co.next_virtual -= 1
	co.mounts[uid] = {"id": weapon_id, "pos": cell_pos, "virtual": true, "powered": powered}
	return uid


## Set the helm input of ship `idx`: throttle and turn, each -1..1.
func set_input(idx: int, throttle: float, turn: float) -> void:
	ships[idx].input = {"throttle": throttle, "turn": turn}


## Fire mount `uid` of ship `idx` at the world point `aim`. False when it cannot (see Weapons.can_fire).
func fire(idx: int, uid: int, aim: Vector2) -> bool:
	return weapons.fire(self, idx, uid, aim)


## Seconds until mount `uid` of ship `idx` may fire again (0 when ready).
func cooldown_left(idx: int, uid: int) -> float:
	return maxf(0.0, (int(ships[idx].cooldowns.get(uid, 0)) - tick) * SUBSTEP)


## Advance `dt` seconds in whole substeps of 1/60 s; a remainder waits for the next call.
func step(dt: float) -> void:
	_acc += dt
	var n := int(_acc / SUBSTEP + 1e-6)
	_acc = maxf(_acc - n * SUBSTEP, 0.0)
	for i in n:
		_substep()


func _substep() -> void:
	tick += 1
	for i in ships.size():
		sync(i)
		var co = ships[i]
		var fly: bool = not co.wrecked and co.flight.can_fly(co.ship.components, co.powered) == ""
		co.flight.step(SUBSTEP, co.input if fly else {}, co.mass, co.thrust)
		Shields.tick(co, SUBSTEP)
	weapons.tick_beams(self)
	Projectiles.step(self, SUBSTEP)


## Recompute power, mass, thrust and the shield cap of ship `idx` if a part or tile changed.
func sync(idx: int) -> void:
	if ships[idx].dirty:
		_recompute(ships[idx])


func _recompute(co) -> void:
	var off := {}
	for uid in co.ship.components.instances:
		if co.ship.components.instances[uid].get("status", "") == "disabled":
			off[uid] = true
	co.powered = Power.solve(co.ship.components, co.ship.cables, off)["powered"]
	co.mass = co.flight.mass_of(co.ship.grid, co.ship.components, co.ship.cables)
	co.thrust = co.flight.thrust_of(co.ship.components, co.powered)
	Shields.resync(co)
	co.dirty = false


## Hull integrity reached 0: ship `idx` is wrecked. It stays in the arena as a derelict.
func wreck(idx: int) -> void:
	var co = ships[idx]
	co.wrecked = true
	co.hull = 0.0
	co.dirty = true
	sync(idx)
	log_event("wreck", idx)


func log_event(type: String, ship: int, cell := Vector2i(-1, -1), extra := {}) -> void:
	var e := {"tick": tick, "type": type, "ship": ship, "cell": cell}
	e.merge(extra)
	events.append(e)


## A world point in ship `idx`'s grid, in (fractional) cell coordinates.
func world_to_local(idx: int, world: Vector2) -> Vector2:
	var co = ships[idx]
	return (world - co.flight.pos).rotated(-co.flight.angle) / CELL + co.pivot


## A point of ship `idx`'s grid (fractional cell coordinates) in the world.
func local_to_world(idx: int, local: Vector2) -> Vector2:
	var co = ships[idx]
	return ((local - co.pivot) * CELL).rotated(co.flight.angle) + co.flight.pos


## The grid cell of ship `idx` under a world point.
func world_to_cell(idx: int, world: Vector2) -> Vector2i:
	var l := world_to_local(idx, world)
	return Vector2i(floori(l.x), floori(l.y))


## The world position of the centre of grid cell `cell` of ship `idx`.
func cell_to_world(idx: int, cell: Vector2i) -> Vector2:
	return local_to_world(idx, Vector2(cell) + Vector2(0.5, 0.5))


## Everything that matters for replay, as plain data (compare two arenas, or hash it).
func snapshot() -> Dictionary:
	var list := []
	for co in ships:
		var parts := {}
		for uid in co.ship.components.instances:
			var inst: Dictionary = co.ship.components.instances[uid]
			parts[str(uid)] = [inst.get("hp", -1), inst.get("status", "")]
		list.append({"pos": [co.flight.pos.x, co.flight.pos.y], "vel": [co.flight.vel.x, co.flight.vel.y], "angle": co.flight.angle,
			"hull": co.hull, "wrecked": co.wrecked, "layers": co.layers, "ion_lock": co.ion_lock,
			"grid": co.ship.grid.to_dict(), "parts": parts})
	return {"tick": tick, "ships": list, "projectiles": projectiles.size(), "events": events.size(), "power_bonus": power_bonus.duplicate()}
