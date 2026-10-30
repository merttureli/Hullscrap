extends RefCounted
## One person walking inside the ship. Plain data and rules: no nodes, no drawing.
## `pos` is the centre of the body in cell units. The body is 2x2 cells (see Pathfinder.BODY): it
## sits on the four cells round `pos`, and collides as a circle of RADIUS (a little under a cell,
## so a 2-wide opening lets it through). NPCs follow a `path` of body anchors (go_to + step), whose
## body centre is the anchor plus (1, 1); the player's soldier moves directly (move_input).
## Health and the current job live here too (rules in jobs.gd); the defaults are in data/crew.json.

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Content = preload("res://scripts/data/content.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const RADIUS := 0.9  ## body radius in cells, used for wall collision (a body is 2 cells wide)
const MAX_SUBSTEP := 0.2  ## longest single move in cells, so a long frame cannot skip over a wall
const CONFIG_PATH := "res://data/crew.json"
const SPECIES_PATH := "res://data/species.json"
const BASE_SPEED := 3.0  ## cells per second for a species with speed 1.0

static var _config := {}  # data/crew.json, read on first use
static var _species := {}  # data/species.json, read on first use

var name := ""
var species := "human"  ## the species id (data/species.json): hp, speed, traits, art rig and sidearm
var gear_traits: Array = []  ## traits worn gear gives (an EVA suit gives "suit"); nothing equips gear yet
var pos := Vector2.ZERO
var speed := BASE_SPEED  ## cells per second
var facing := Vector2.DOWN
var path: Array[Vector2i] = []
var hp := 100.0
var max_hp := 100.0
var is_player := false  ## the player's soldier: moved by hand, never given a job
var look := {}  ## PersonDrawer palette ("suit", "hair", "tool"); empty = the viewer picks one by name
var job := {}  ## what they are doing now (a Jobs board entry plus its "spot"); empty = idle
var hold := 0.0  ## seconds left of a manual order, during which the job board leaves them alone
var stun := 0.0  ## seconds left stunned (an ion hit on their room, trait ion_stun): no walking, no work


func _init(p_name := "", p_pos := Vector2.ZERO, p_species := "human") -> void:
	name = p_name
	pos = p_pos
	set_species(p_species)


## data/crew.json as a Dictionary (read once; empty when the file is missing or unusable).
static func config() -> Dictionary:
	if _config.is_empty() and FileAccess.file_exists(CONFIG_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if data is Dictionary:
			_config = data
	return _config


## data/species.json as a Dictionary: {default, species} (read once, with the packs' species; empty when the file is missing or unusable).
static func species_table() -> Dictionary:
	if _species.is_empty() and FileAccess.file_exists(SPECIES_PATH):
		var data = Content.read(SPECIES_PATH)  # core plus any packs' species
		if data is Dictionary:
			_species = data
	return _species


## The entry of species `id` in data/species.json; {} for an id it does not list.
static func species_def(id: String) -> Dictionary:
	var d = species_table().get("species", {}).get(id)
	return d if d is Dictionary else {}


## Become species `id`: max hp and walk speed come from its entry (the crew.json hp, and speed 1.0,
## for an id data/species.json does not list) times the hp_mult and speed_mult of their traits (TraitSet,
## the species' and personal ones; gear worn later does not change the body), and hp is full.
func set_species(id: String) -> void:
	species = id
	var def := species_def(id)
	var t := TraitSet.of(self)
	max_hp = float(def.get("hp", config().get("hp", 100))) * float(t["hp_mult"])
	hp = max_hp
	speed = BASE_SPEED * float(def.get("speed", 1.0)) * float(t["speed_mult"])


## Every trait this person has, without repeats: their species' (data/species.json), their own
## (data/crew.json `traits`, by name) and the ones worn gear gives (`gear_traits`).
func traits() -> Array:
	var out := []
	for list in [species_def(species).get("traits", []), config().get("traits", {}).get(name, []), gear_traits]:
		for t in list:
			if not out.has(t):
				out.append(t)
	return out


## The art folder this person is drawn with (art/crew/<rig>/): their species' `rig`, else the species id.
func rig() -> String:
	return str(species_def(species).get("rig", species))


## The hand weapon they carry (an id of data/hand_weapons.json), "" when their species has none.
func sidearm() -> String:
	return str(species_def(species).get("sidearm", ""))


## Stunned (ion, see TraitSet): they neither walk nor work until `stun` runs out.
func is_stunned() -> bool:
	return stun > 0.0


## At 0 hp a crew member is down: they don't move and no job is given, until a medbay or a crewmate revives them.
func is_down() -> bool:
	return hp <= 0.0


## Lose `amount` hp (not below 0).
func hurt(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)


## Gain `amount` hp (not above the maximum).
func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)


## The cell under the centre of the body (the room whose air this person breathes).
func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


## The top-left cell of the 2x2 cells the body covers.
func anchor() -> Vector2i:
	return Pathfinder.anchor_of(pos)


## The 2x2 cells the body covers.
func body_cells() -> Array[Vector2i]:
	return Pathfinder.body_cells(anchor())


## Walk until the body sits on anchor `target` (see Pathfinder), along the shortest path from the
## nearest usable anchor. Returns false (and keeps the current path) when there is no route.
func go_to(grid: ShipGrid, target: Vector2i, door_passable: Callable = Callable()) -> bool:
	var from := Pathfinder.nearest_walkable(grid, pos, door_passable)
	var p := Pathfinder.find_path(grid, from, target, door_passable)
	if p.is_empty():
		return false
	path = p
	return true


## Advance along the path, centre to centre. Ends exactly on the last anchor's body centre.
func step(dt: float) -> void:
	if is_down():
		path.clear()
		return
	if is_stunned():
		return
	var left := speed * dt
	while left > 0.0 and not path.is_empty():
		var to := Pathfinder.centre_of(path[0])
		var d := to - pos
		var dist := d.length()
		if dist > 0.0:
			facing = d / dist
		if dist <= left:
			pos = to
			left -= dist
			path.remove_at(0)
		else:
			pos += facing * left
			left = 0.0


## The player's direct movement: `dir` (any length) x speed x dt, one axis at a time so the
## body slides along walls. A move that would put the body into a non-walkable cell is dropped.
## Doorway assist: walking straight at an opening a little off line, the body drifts sideways onto
## the line that lets it through (a 2-wide door leaves only 0.2 cells to spare).
func move_input(grid: ShipGrid, dir: Vector2, dt: float, door_passable: Callable = Callable()) -> void:
	if is_down() or is_stunned() or dir.length_squared() < 0.0001 or dt <= 0.0:
		return
	facing = dir.normalized()
	var dist := speed * dt
	var n := maxi(1, ceili(dist / MAX_SUBSTEP))
	var d := facing * (dist / n)
	for i in n:
		if fits(grid, pos + Vector2(d.x, 0.0), door_passable):
			pos.x += d.x
		elif d.y == 0.0:
			_slide_to_lane(grid, Vector2(d.x, 0.0), door_passable)
		if fits(grid, pos + Vector2(0.0, d.y), door_passable):
			pos.y += d.y
		elif d.x == 0.0:
			_slide_to_lane(grid, Vector2(0.0, d.y), door_passable)


## Blocked head-on while moving by `step` (along one axis): nudge sideways, at most `step` long,
## toward the nearest whole-number line from which the step would fit.
func _slide_to_lane(grid: ShipGrid, step: Vector2, door_passable: Callable) -> void:
	var a := 0 if step.x != 0.0 else 1  # the axis we move along; 1 - a is the sideways one
	var side := 1 - a
	var lanes := [floorf(pos[side]), ceilf(pos[side])]
	if lanes[0] == lanes[1]:
		return  # already on a line: a real wall
	if pos[side] - lanes[0] > lanes[1] - pos[side]:
		lanes.reverse()  # nearest first
	for lane: float in lanes:
		var ahead := pos + step
		ahead[side] = lane
		if not fits(grid, ahead, door_passable):
			continue
		var to := pos
		to[side] += clampf(lane - pos[side], -absf(step[a]), absf(step[a]))
		if fits(grid, to, door_passable):
			pos = to
		return


## Would a body of `radius` centred on `p` stay clear of every non-walkable cell?
func fits(grid: ShipGrid, p: Vector2, door_passable: Callable = Callable(), radius := RADIUS) -> bool:
	for cy in range(floori(p.y - radius), floori(p.y + radius) + 1):
		for cx in range(floori(p.x - radius), floori(p.x + radius) + 1):
			if Pathfinder.walkable(grid, Vector2i(cx, cy), door_passable):
				continue
			var near := Vector2(clampf(p.x, cx, cx + 1), clampf(p.y, cy, cy + 1))
			if (p - near).length_squared() < radius * radius:
				return false
	return true


## Fix up after the ship changed under us (a wall built on the body, a door shut): when the body
## overlaps a non-walkable cell, move it onto the nearest usable anchor, then re-plan or drop a
## path that now crosses an anchor the body can't stand on.
func resolve(grid: ShipGrid, door_passable: Callable = Callable()) -> void:
	if not fits(grid, pos, door_passable, RADIUS - 0.01):
		var n := Pathfinder.nearest_walkable(grid, pos, door_passable)
		if n == Pathfinder.NO_CELL:
			return
		pos = Pathfinder.centre_of(n)
	for c in path:
		if not Pathfinder.body_ok(grid, c, door_passable):
			if not go_to(grid, path.back(), door_passable):
				path.clear()
			break
