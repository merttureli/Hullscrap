extends RefCounted
## Bleeding out (docs/MECHANICS_REVIEW.md P4): a crew member at 0 hp dies after crew.json `bleed_out_s`
## seconds, unless a crewmate is working a revive on them right now or they lie in a room with a powered,
## working medbay (the timer stops, it does not reset). Back above 0 hp, the timer starts over. The player's
## soldier never dies: they stay down. The same rule for every ship, enemies included. A dead member leaves
## ship.crew, any station they manned and the job of anyone who was coming to save them, and their name goes
## on ship.dead_crew so Jobs.spawn_crew does not bring them back. Two traits change it (traits.gd):
## - revive_once {after, hp}: the first time they go down they do not bleed; `after` seconds later they stand up
##   at `hp` (the crewmates' revive job leaves them alone meanwhile). Once a run (CrewMember.revived). If they are
##   picked up first, the revive is spent all the same.
## - split_on_death {reform_s}: bleeding out they do not die: they become two small 1x1 halves with half the max hp
##   each, full (the original keeps the name, the other is "<name> b"). If both are still aboard and up `reform_s`
##   seconds later they merge into the original again, at the sum of their hp (a downed half holds the merge back
##   until it is up, or dead). If one dies the other stays small for good (a half never splits again). No nodes, no drawing.

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const DEFAULT_BLEED_S := 45.0


## Seconds a downed member lasts (data/crew.json `bleed_out_s`).
static func bleed_out_s() -> float:
	return float(CrewMember.config().get("bleed_out_s", DEFAULT_BLEED_S))


## How far gone `m` is, 0..1, for the red ring: 0 for anyone standing and for the player's soldier (who never dies).
static func bleed_frac(m) -> float:
	if not m.is_down() or m.is_player:
		return 0.0
	return clampf(m.down_t / maxf(bleed_out_s(), 0.001), 0.0, 1.0)


## Advance the bleeding of every downed member of `ship` by `dt` seconds, then the halves of split bodies. Returns the
## chronicle lines ("Rook has died.", "Tess splits in two.", "Tess rises again.") of this tick.
static func tick(ship, dt: float) -> Array:
	var lines := []
	var limit := bleed_out_s()
	var dying := []
	for m in ship.crew:
		if not m.is_down():
			m.down_t = 0.0
			m.revive_t = -1.0
		elif _rising(m, dt, lines):
			m.down_t = 0.0  # a revive is pending: the bleeding waits
		elif not m.is_player and not _saved(ship, m):
			m.down_t += dt
			if m.down_t >= limit:
				dying.append(m)
	_reform(ship, dt, lines)  # before the splits, so the tick a body splits is not counted
	for m in dying:
		if not ship.crew.has(m):  # a half that merged this very tick
			continue
		if _split(ship, m):
			lines.append("%s splits in two." % m.name)
		else:
			_die(ship, m)
			lines.append("%s has died." % m.name)
	return lines


## Is the downed `m` held by a revive_once? The first tick down arms it (once: `revived`); `after` seconds later
## they stand up at the trait's hp. True while it is pending and in the tick they rise.
static func _rising(m, dt: float, lines: Array) -> bool:
	var rv: Dictionary = TraitSet.of(m)["revive_once"]
	if m.revive_t < 0.0:  # went down just now
		if m.revived or float(rv["hp"]) <= 0.0:
			return false
		m.revived = true
		m.revive_t = 0.0
	elif float(rv["hp"]) <= 0.0:  # the trait is gone (the gear came off)
		m.revive_t = -1.0
		return false
	m.revive_t += dt
	if m.revive_t >= float(rv["after"]) - 1e-6:
		m.hp = minf(float(rv["hp"]), m.max_hp)
		m.revive_t = -1.0
		lines.append("%s rises again." % m.name)
	return true


## Is `m` being saved right now: a crewmate at their side working a revive, or a powered medbay in their room?
static func _saved(ship, m) -> bool:
	var key: String = "revive:" + m.name
	for c in ship.crew:
		if c == m or c.is_down() or c.is_stunned() or str(c.job.get("key", "")) != key:
			continue
		if bool(c.job.get("hand", false)):  # the player's hand on the job: only while they keep at it
			if ship.clock - float(c.job.get("t", -1.0e9)) < Jobs.HAND_SHOWN:
				return true
		elif c.path.is_empty() and _beside(c, m):
			return true
	var room: int = ship.atmosphere.room_at(m.cell())
	if room < 0:
		return false
	var powered: Dictionary = ship.power_state.get("powered", {})
	for uid in ship.components.instances:
		var inst: Dictionary = ship.components.instances[uid]
		if ship.components.def(inst["id"]).get("family", "") == "medbay" and inst["status"] == "ok" and bool(powered.get(uid, false)):
			for cell in inst["cells"]:
				if ship.atmosphere.room_at(cell) == room:
					return true
	return false


## Do the bodies of `a` and `b` touch (a cell of one within one step of a cell of the other)?
static func _beside(a, b) -> bool:
	for p in a.body_cells():
		for q in b.body_cells():
			if absi(p.x - q.x) + absi(p.y - q.y) <= 1:
				return true
	return false


## Take `m` off the ship: out of the crew, off any station, and whoever was on their way to them is freed.
static func _die(ship, m) -> void:
	_leave(ship, m)
	ship.dead_crew.append(m.name)
	var twin = _find(ship, m.split_pair)  # the other half of a split body stays, small
	if twin != null:
		twin.split_pair = ""
		twin.split_t = -1.0


## `m` is gone from the crew (dead, or merged back into their other half): off the list, off any station they manned,
## and whoever was on their way to them is freed.
static func _leave(ship, m) -> void:
	ship.crew.erase(m)
	for uid in ship.manned.keys():
		if ship.manned[uid] == m.name:
			ship.manned.erase(uid)
	_free_helpers(ship, m)
	m.job = {}
	m.path.clear()


static func _free_helpers(ship, m) -> void:
	for c in ship.crew:
		if str(c.job.get("who", "")) == m.name:
			c.job = {}
			c.path.clear()


static func _find(ship, who: String):
	if who != "":
		for c in ship.crew:
			if c.name == who:
				return c
	return null


## `m` has bled out. With split_on_death (and not yet a half) they do not die: they stand up as two 1x1 halves on two
## cells of the body they had, each with half the max hp, full, and a clock of reform_s starts. False when they just die.
static func _split(ship, m) -> bool:
	var reform := float(TraitSet.of(m)["split_on_death"]["reform_s"])
	if reform <= 0.0 or m.is_half:
		return false
	var cells: Array[Vector2i] = m.body_cells()  # before the body shrinks
	var other_name: String = m.name + " b"
	while _find(ship, other_name) != null or ship.dead_crew.has(other_name):
		other_name += "'"
	var other = CrewMember.new(other_name, Pathfinder.centre_of(cells[-1], 1), m.species)
	other.look = m.look.duplicate()
	other.gear_traits = m.gear_traits.duplicate()
	other.ability = m.ability.duplicate(true)
	other.body_size = 1
	other.max_hp = m.max_hp * 0.5
	other.hp = other.max_hp
	other.is_half = true
	other.split_pair = m.name
	m.body_size = 1
	m.max_hp *= 0.5
	m.hp = m.max_hp
	m.pos = Pathfinder.centre_of(cells[0], 1)
	m.is_half = true
	m.split_pair = other_name
	m.split_t = 0.0
	m.down_t = 0.0
	m.path.clear()
	m.job = {}
	_free_helpers(ship, m)
	ship.crew.insert(ship.crew.find(m) + 1, other)
	return true


## The original half of every split body counts the seconds the halves are apart; at reform_s, with both aboard and up, they
## merge: the original is whole again (the trait's body, the summed max hp) at the sum of the halves' hp, on the
## nearest spot a whole body fits, and the other half is gone.
static func _reform(ship, dt: float, lines: Array) -> void:
	for m in ship.crew.duplicate():
		if m.split_t < 0.0 or m.split_pair == "":
			continue
		var other = _find(ship, m.split_pair)
		if other == null:
			m.split_pair = ""
			m.split_t = -1.0
			continue
		m.split_t += dt
		if m.split_t < float(TraitSet.of(m)["split_on_death"]["reform_s"]) - 1e-6 or m.is_down() or other.is_down():
			continue  # not yet; a downed half has to be on its feet (or dead) first
		var body := int(TraitSet.of(m)["body"])
		var spot := Pathfinder.nearest_walkable(ship.grid, m.pos, Callable(), Pathfinder.NO_CELL, body)
		if spot == Pathfinder.NO_CELL:
			continue  # no room for a whole body yet: try again next tick
		_leave(ship, other)
		m.body_size = body
		m.max_hp += other.max_hp
		m.hp = minf(m.hp + other.hp, m.max_hp)
		m.pos = Pathfinder.centre_of(spot, body)
		m.is_half = false
		m.split_pair = ""
		m.split_t = -1.0
		m.path.clear()
		m.job = {}
		lines.append("%s reforms." % m.name)
