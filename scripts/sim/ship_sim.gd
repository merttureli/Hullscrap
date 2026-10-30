extends Node
## Runs the game's ships every frame. It holds the list of ships (the first is the player's); each
## frame, per ship: refresh the derived state if the structure changed, let powered oxygen
## generators add air, let the crew breathe, then let the atmosphere flow.
## Auto doors: a door counts as open for the atmosphere while a crew member stands on it.
## step() does one tick without the scene tree, so tests can drive it.

const Ship = preload("res://scripts/ship/ship.gd")
const BREATH_RATE := 0.02  ## air one crew member uses, in cell units per second
const MAX_FRAME := 0.25  ## longest time step a slow frame may take, seconds

var ships: Array = []


func _init() -> void:
	ships.append(Ship.new_starter())


## The ship the player controls and builds on.
func player_ship() -> Ship:
	return ships[0] if not ships.is_empty() else null


func _process(dt: float) -> void:
	step(minf(dt, MAX_FRAME))


## Advance every ship by `dt` seconds.
func step(dt: float) -> void:
	for ship in ships:
		_step_ship(ship, dt)


func _step_ship(ship: Ship, dt: float) -> void:
	ship.refresh()
	var open: Dictionary = ship.grid.door_open.duplicate()
	for m in ship.crew:
		if ship.grid.tile_flag(ship.grid.get_tile(m.cell()), "door"):
			open[m.cell()] = true
	var powered: Dictionary = ship.power_state.get("powered", {})
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		var rate := float(ship.components.def(inst["id"]).get("stats", {}).get("o2_rate", 0.0))
		if rate > 0.0 and powered.get(uid, false):
			ship.atmosphere.add_oxygen(ship.atmosphere.room_at(inst["anchor"]), rate * dt)
	for m in ship.crew:
		ship.atmosphere.consume(ship.atmosphere.room_at(m.cell()), BREATH_RATE * dt)
	ship.atmosphere.tick(dt, open)
