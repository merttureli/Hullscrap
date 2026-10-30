extends Node
## Runs the game's ships every frame. It holds the list of ships (the first is the player's); each
## frame, per ship: refresh the derived state if the structure changed, heat up and cool down the
## components, roll their malfunctions, let powered oxygen generators add air, let the crew
## breathe, burn the fires, let the crew work (jobs.gd: walk, repair, fight fires, man stations,
## heal), then let the atmosphere flow. A ship that is not the player's gets its own crew on its
## first tick (Jobs.spawn_enemy_crew).
## Abilities (abilities.gd) tick here while one ship is in the sim; in a fight (more than one) the
## arena ticks them itself, at its own rate. The fabricator's queue (ship.crafting) ticks for every
## ship, at the level and tools of the ship's best powered fabricator (Workshop.best); finished
## items go to the cargo and the chronicle says so, and says when the fabricator stops the queue.
## The random rolls (malfunctions, fires) use one RandomNumberGenerator per ship, seeded with the
## ship's rng_seed (default 1), so the same ship and inputs always play out the same.
## Auto doors: a door piece counts as open for the atmosphere while any crew body overlaps any of
## its cells. Crew breathe the room under the centre of their body.
## step() does one tick without the scene tree, so tests can drive it.

const Ship = preload("res://scripts/ship/ship.gd")
const Heat = preload("res://scripts/sim/heat.gd")
const Reliability = preload("res://scripts/sim/reliability.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")
const BREATH_RATE := 0.02  ## air one crew member uses, in cell units per second
const MAX_FRAME := 0.25  ## longest time step a slow frame may take, seconds

var ships: Array = []
var design_path := ""  ## the design file the player's ship was last loaded from; "" for the empty starter hull
var _rngs := {}  # ship -> its RandomNumberGenerator
var _jobs := {}  # ship -> its Jobs board
var _crewed := {}  # ship -> true once its own crew was spawned
var _ability_label: Label  # the HUD line of the running abilities, made in _ready when the scene has a HUD


func _init() -> void:
	ships.append(Ship.new_starter())


## The ship the player controls and builds on.
func player_ship() -> Ship:
	return ships[0] if not ships.is_empty() else null


## Replace the player's ship with the design in `path` (Ship.from_design): its crew, chronicle and
## random rolls start afresh. "" when it worked, else why not (nothing changes then).
func choose_ship(path: String) -> String:
	var ship: Ship = Ship.from_design(path)
	if ship == null:
		return "cannot load " + path
	if ships.is_empty():
		ships.append(ship)
	else:
		_rngs.erase(ships[0])
		_jobs.erase(ships[0])
		_crewed.erase(ships[0])
		ships[0] = ship
	design_path = path
	return ""


func _ready() -> void:
	var hud := get_node_or_null("../HUD")
	if hud == null:
		return
	_ability_label = Label.new()
	_ability_label.anchor_left = 1.0
	_ability_label.anchor_right = 1.0
	_ability_label.offset_left = -520.0
	_ability_label.offset_right = -14.0
	_ability_label.offset_top = 216.0
	_ability_label.offset_bottom = 244.0
	_ability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ability_label.add_theme_color_override("font_color", Color("#ffd24a"))
	_ability_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_ability_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_ability_label)


func _process(dt: float) -> void:
	step(minf(dt, MAX_FRAME))
	if _ability_label != null:
		_ability_label.text = hud_line()


## The HUD line for the abilities running on the player's ship ("" when none): "Abilities: Afterburn 5 s".
func hud_line() -> String:
	var ship := player_ship()
	return Abilities.hud_line(ship) if ship != null else ""


## Advance every ship by `dt` seconds.
func step(dt: float) -> void:
	for ship in ships:
		_step_ship(ship, dt)
	for table in [_jobs, _crewed]:  # forget ships that left (a fight is over)
		for ship in table.keys():
			if not ships.has(ship):
				table.erase(ship)


## The random number generator of `ship`, made on first use from ship.rng_seed.
func rng_of(ship: Ship) -> RandomNumberGenerator:
	if not _rngs.has(ship):
		var rng := RandomNumberGenerator.new()
		rng.seed = ship.rng_seed
		_rngs[ship] = rng
	return _rngs[ship]


## The job board and crew rules of `ship`, made on first use.
func jobs_of(ship: Ship) -> Jobs:
	if not _jobs.has(ship):
		_jobs[ship] = Jobs.new()
	return _jobs[ship]


## The door cells that are open right now: the doors someone opened (grid.door_open) plus every door
## piece that a crew body overlaps (auto doors). Cell -> true.
static func open_door_cells(ship: Ship) -> Dictionary:
	var open: Dictionary = ship.grid.door_open.duplicate()
	for m in ship.crew:
		for c in m.body_cells():
			if ship.grid.tile_flag(ship.grid.get_tile(c), "door"):
				for p in ship.grid.door_piece(c):
					open[p] = true
	return open


func _step_ship(ship: Ship, dt: float) -> void:
	ship.refresh()
	ship.clock += dt
	var rng := rng_of(ship)
	if ships.size() == 1:  # in a fight the arena ticks the abilities
		Abilities.tick(ship, dt, rng)
	Heat.tick(ship, dt, rng)
	Reliability.tick(ship, dt, rng)
	ship.refresh()  # a part that went out of action or came back changes the power
	_craft(ship, dt)
	var powered: Dictionary = ship.power_state.get("powered", {})
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		var rate: float = ship.effective(inst["id"])["stats"].get("o2_rate", 0.0)
		if rate > 0.0 and powered.get(uid, false):
			ship.atmosphere.add_oxygen(ship.atmosphere.room_at(inst["anchor"]), rate * dt)
	if ship != player_ship() and not _crewed.has(ship):
		if not ship.crew.is_empty() or not Jobs.spawn_enemy_crew(ship).is_empty():
			_crewed[ship] = true
	for m in ship.crew:
		if not m.traits().has("no_breath"):  # Basalt don't use the air
			ship.atmosphere.consume(ship.atmosphere.room_at(m.cell()), BREATH_RATE * dt)
	Fire.tick(ship, dt, rng)
	jobs_of(ship).tick(ship, dt, ships.size() > 1)  # more than one ship aboard the sim: a fight
	ship.atmosphere.tick(dt, open_door_cells(ship))


## Run the fabricator's queue of `ship` for `dt` seconds and tell the chronicle what happened.
func _craft(ship: Ship, dt: float) -> void:
	var c = ship.crafting
	if c.queue.is_empty():
		return
	var fab := Workshop.best(ship)
	var was: bool = c.paused
	for id in c.tick(dt, ship.inventory, fab):
		ship.log_event("Crafted " + c.name_of(c.def(id)["output"]["item"], ship.components))
	if c.paused and not was:
		if int(fab["level"]) <= 0:
			ship.log_event("Fabricator offline: crafting paused")
		else:
			ship.log_event("Fabricator too weak for %s: crafting paused" % c.name_of(c.def(c.queue[0]["recipe"])["output"]["item"], ship.components))
	elif was and not c.paused:
		ship.log_event("Fabricator online: crafting resumed")
