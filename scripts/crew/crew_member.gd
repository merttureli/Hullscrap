extends RefCounted
## One person walking inside the ship. Plain data and rules: no nodes, no drawing.
## `pos` is the centre of the body in cell units. The body is 2x2 cells (see Pathfinder.BODY): it
## sits on the four cells round `pos`, and collides as a circle of RADIUS (a little under a cell,
## so a 2-wide opening lets it through). NPCs follow a `path` of body anchors (go_to + step), whose
## body centre is the anchor plus (1, 1); the player's soldier moves directly (move_input).
## A small body (the trait `body` 1, `body_size`) is one cell, with half the radius: it also fits 1-wide crawlspaces.
## Health and the current job live here too (rules in jobs.gd); the defaults are in data/crew.json.

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Content = preload("res://scripts/data/content.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const Characters = preload("res://scripts/crew/characters.gd")
const RADIUS := 0.9  ## body radius in cells, used for wall collision (a body is 2 cells wide; a small one has half of it, see body_radius)
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
var speed_mod := 1.0  ## factor on `speed` right now (the heat of their room, trait heat_speed): Jobs sets it every tick
var body_size := Pathfinder.BODY  ## cells across the body: 2, or 1 for a small body (trait `body`, read when the species is set)
var mend_t := 0.0  ## seconds a hull_mend crew member has spent sealing the breach next to them (Jobs)
var revived := false  ## their revive_once is spent: they went down once already (Mortality). The crew live as long as the run does, so it is once a run
var revive_t := -1.0  ## seconds a revive_once has been pending since they went down; -1 = none pending (Mortality)
var mimicking: Array = []  ## the trait ids a `mimic` copies right now (TraitSet.update_mimics, set by Jobs.tick); TraitSet.of merges their keys. Not saved
var is_half := false  ## one of the two halves of a split_on_death body: it does not split again, and stays small when the other half dies (Mortality)
var split_pair := ""  ## while the two halves are apart: the name of the other half, "" otherwise
var split_t := -1.0  ## on the half that counts (the original): seconds the halves have been apart; -1 on the other one
var facing := Vector2.DOWN
var path: Array[Vector2i] = []
var hp := 100.0
var max_hp := 100.0
var is_player := false  ## the player's soldier: moved by hand, never given a job
var look := {}  ## PersonDrawer palette ("suit", "hair", "tool"); empty = the viewer picks one by name
var job := {}  ## what they are doing now (a Jobs board entry plus its "spot"); empty = idle
var hold := 0.0  ## seconds left of a manual order, during which the job board leaves them alone
var stun := 0.0  ## seconds left stunned (an ion hit on their room, trait ion_stun): no walking, no work
var down_t := 0.0  ## seconds spent at 0 hp (mortality.gd: they die at crew.json bleed_out_s unless someone is saving them)
var ability: Dictionary = {}  ## the active ability they carry, {id, cooldown?, params?} (crew_abilities.gd): their species' own, or their character's
var ability_cd := 0.0  ## seconds until the ability may be used again (ticked by CrewAbilities.tick, so build mode pauses it)
var character := ""  ## the unique character (data/characters.json) they are, "" for an ordinary crew member
var head := ""  ## a head frame of their rig's art to draw instead of the usual one ("" = the usual); a character's rig.head
var _drone := false  # the species is a repair drone (set_species)


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


## The entry of species `id` in data/species.json; {} for an id it does not list (a character's one-of-a-kind
## species, "unique:<id>", is found in data/characters.json).
static func species_def(id: String) -> Dictionary:
	var d = species_table().get("species", {}).get(id)
	return d if d is Dictionary else Characters.unique_species(id)


## Become species `id`: max hp and walk speed come from its entry (the crew.json hp, and speed 1.0,
## for an id data/species.json does not list) times the hp_mult and speed_mult of their traits (TraitSet,
## the species' and personal ones; gear worn later does not change the body), and hp is full. The species'
## `ability` (if it has one) becomes theirs.
func set_species(id: String) -> void:
	species = id
	var def := species_def(id)
	ability = def["ability"].duplicate(true) if def.get("ability") is Dictionary else {}
	var t := TraitSet.of(self)
	max_hp = float(def.get("hp", config().get("hp", 100))) * float(t["hp_mult"])
	hp = max_hp
	speed = BASE_SPEED * float(def.get("speed", 1.0)) * float(t["speed_mult"])
	body_size = int(t["body"])
	_drone = bool(def.get("drone", false))


## A repair drone (playtest 2, R1; species `drone: true`)? It is a body that works like crew but is not crew: leave it out of
## crew counts, beds and morale, never steer or give it orders, and when it is at 0 hp it is broken, not dying (is_down;
## Mortality, Jobs). What it may do: data/crew.json `drone_jobs`.
func is_drone() -> bool:
	return _drone


## Is species `id` a repair drone?
static func is_drone_species(id: String) -> bool:
	return bool(species_def(id).get("drone", false))


## Every trait this person has, without repeats: their species' (data/species.json), their own
## (data/crew.json `traits`, by name), their character's (when its `traits` is a list of ids) and the ones worn
## gear gives (`gear_traits`).
func traits() -> Array:
	var out := []
	for list in [species_def(species).get("traits", []), config().get("traits", {}).get(name, []), Characters.trait_ids(character), gear_traits]:
		for t in list:
			if not out.has(t):
				out.append(t)
	return out


## "" when this person may wear the gear that gives trait `id`, else why not ("<name> cannot wear a suit or armour": the
## no_suit trait refuses the SUIT_TRAITS). Nothing else is refused.
func can_wear(id: String) -> String:
	if TraitSet.SUIT_TRAITS.has(id) and TraitSet.of(self)["no_suit"]:
		return "%s cannot wear a suit or armour" % name
	return ""


## Wear the gear that gives trait `id` (it joins `gear_traits`). Returns "" when worn, else the reason it was refused (can_wear).
func equip(id: String) -> String:
	var why := can_wear(id)
	if why == "" and not gear_traits.has(id):
		gear_traits.append(id)
	return why


## A new crew member that is the unique character `id` (Characters.apply), standing at `p_pos`. Null for an unknown id.
static func from_character(id: String, p_pos := Vector2.ZERO):
	var m = new("", p_pos)
	return m if Characters.apply(m, id) else null


## Everything a save keeps of this person, as JSON-friendly data (Ship.to_dict "crew_state"; from_dict is the way back):
## who they are (name, species, soldier, character, look, head, worn gear), how they are (hp, down and bleeding, the
## ability's cooldown, a revive spent, a split) and where they stand. What they are doing (job, path, orders) is not
## kept: the job board hands out work again.
func to_dict() -> Dictionary:
	var d := {"name": name, "species": species, "pos": [pos.x, pos.y], "hp": hp, "max_hp": max_hp}
	if is_player:
		d["is_player"] = true
	if character != "":
		d["character"] = character
	if not look.is_empty():
		var colours := {}
		for k in look:
			colours[str(k)] = look[k].to_html() if look[k] is Color else look[k]
		d["look"] = colours
	if head != "":
		d["head"] = head
	if not gear_traits.is_empty():
		d["gear"] = gear_traits.duplicate()
	if ability_cd > 0.0:
		d["ability_cd"] = ability_cd
	if down_t > 0.0:
		d["down_t"] = down_t
	if revived:
		d["revived"] = true
	if revive_t >= 0.0:
		d["revive_t"] = revive_t
	if mend_t > 0.0:
		d["mend_t"] = mend_t
	if is_half:
		d["is_half"] = true
	if split_pair != "":
		d["split_pair"] = split_pair
	if split_t >= 0.0:
		d["split_t"] = split_t
	return d


## A person from to_dict() data: made the way Jobs.spawn_crew and Campaign.add_crew make them (a new CrewMember of the
## species, the character applied), then given what was saved. Null when `d` is not a person (no name or place).
static func from_dict(d: Dictionary):
	var p = d.get("pos")
	if not (d.get("name") is String and str(d["name"]) != "" and p is Array and p.size() == 2 and _is_num(p[0]) and _is_num(p[1])):
		return null
	var m = new(str(d["name"]), Vector2(float(p[0]), float(p[1])), str(d.get("species", "human")))
	if str(d.get("character", "")) != "":
		Characters.apply(m, str(d["character"]))  # (an id the data no longer has stays an ordinary person)
		m.name = str(d["name"])
	m.is_player = bool(d.get("is_player", false))
	if d.get("look") is Dictionary:
		m.look = d["look"].duplicate()
	m.head = str(d.get("head", m.head))
	if d.get("gear") is Array:
		for g in d["gear"]:
			if not m.gear_traits.has(str(g)):
				m.gear_traits.append(str(g))
	m.max_hp = maxf(1.0, float(d["max_hp"])) if _is_num(d.get("max_hp")) else m.max_hp
	m.hp = clampf(float(d["hp"]), 0.0, m.max_hp) if _is_num(d.get("hp")) else m.max_hp
	m.ability_cd = maxf(0.0, float(d.get("ability_cd", 0.0))) if _is_num(d.get("ability_cd", 0.0)) else 0.0
	m.down_t = maxf(0.0, float(d.get("down_t", 0.0))) if _is_num(d.get("down_t", 0.0)) else 0.0
	m.revived = bool(d.get("revived", false))
	m.revive_t = float(d.get("revive_t", -1.0)) if _is_num(d.get("revive_t", -1.0)) else -1.0
	m.mend_t = maxf(0.0, float(d.get("mend_t", 0.0))) if _is_num(d.get("mend_t", 0.0)) else 0.0
	m.is_half = bool(d.get("is_half", false))
	m.split_pair = str(d.get("split_pair", ""))
	m.split_t = float(d.get("split_t", -1.0)) if _is_num(d.get("split_t", -1.0)) else -1.0
	return m


static func _is_num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


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


## The top-left cell of the cells the body covers (2x2, or the one cell of a small body).
func anchor() -> Vector2i:
	return Pathfinder.anchor_of(pos, body_size)


## The cells the body covers.
func body_cells() -> Array[Vector2i]:
	return Pathfinder.body_cells(anchor(), body_size)


## The collision radius of the body in cells: RADIUS for a 2x2 body, in proportion for a smaller one.
func body_radius() -> float:
	return RADIUS * body_size / float(Pathfinder.BODY)


## Walk until the body sits on anchor `target` (see Pathfinder), along the shortest path from the
## nearest usable anchor. Returns false (and keeps the current path) when there is no route.
func go_to(grid: ShipGrid, target: Vector2i, door_passable: Callable = Callable()) -> bool:
	var from := Pathfinder.nearest_walkable(grid, pos, door_passable, Pathfinder.NO_CELL, body_size)
	var p := Pathfinder.find_path(grid, from, target, door_passable, body_size)
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
	var left := speed * speed_mod * dt
	while left > 0.0 and not path.is_empty():
		var to := Pathfinder.centre_of(path[0], body_size)
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
	var dist := speed * speed_mod * dt
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
## toward the nearest line (a whole number for a 2x2 body, a cell middle for a 1x1 one) from which the step would fit.
func _slide_to_lane(grid: ShipGrid, step: Vector2, door_passable: Callable) -> void:
	var a := 0 if step.x != 0.0 else 1  # the axis we move along; 1 - a is the sideways one
	var side := 1 - a
	var h := body_size * 0.5  # the body's centre sits on lines at this offset from a whole number
	var lanes := [floorf(pos[side] - h) + h, ceilf(pos[side] - h) + h]
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


## Would a body of `radius` (default: their own, body_radius) centred on `p` stay clear of every non-walkable cell?
func fits(grid: ShipGrid, p: Vector2, door_passable: Callable = Callable(), radius := -1.0) -> bool:
	if radius < 0.0:
		radius = body_radius()
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
	if not fits(grid, pos, door_passable, body_radius() - 0.01):
		var n := Pathfinder.nearest_walkable(grid, pos, door_passable, Pathfinder.NO_CELL, body_size)
		if n == Pathfinder.NO_CELL:
			return
		pos = Pathfinder.centre_of(n, body_size)
	for c in path:
		if not Pathfinder.body_ok(grid, c, door_passable, body_size):
			if not go_to(grid, path.back(), door_passable):
				path.clear()
			break
