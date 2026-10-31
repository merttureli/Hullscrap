extends RefCounted
## Bleeding out (docs/MECHANICS_REVIEW.md P4): a crew member at 0 hp dies after crew.json `bleed_out_s`
## seconds, unless a crewmate is working a revive on them right now or they lie in a room with a powered,
## working medbay (the timer stops, it does not reset). Back above 0 hp, the timer starts over. The player's
## soldier never dies: they stay down. The same rule for every ship, enemies included. A dead member leaves
## ship.crew, any station they manned and the job of anyone who was coming to save them, and their name goes
## on ship.dead_crew so Jobs.spawn_crew does not bring them back. No nodes, no drawing.

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const DEFAULT_BLEED_S := 45.0


## Seconds a downed member lasts (data/crew.json `bleed_out_s`).
static func bleed_out_s() -> float:
	return float(CrewMember.config().get("bleed_out_s", DEFAULT_BLEED_S))


## How far gone `m` is, 0..1, for the red ring: 0 for anyone standing and for the player's soldier (who never dies).
static func bleed_frac(m) -> float:
	if not m.is_down() or m.is_player:
		return 0.0
	return clampf(m.down_t / maxf(bleed_out_s(), 0.001), 0.0, 1.0)


## Advance the bleeding of every downed member of `ship` by `dt` seconds. Returns the chronicle lines
## ("Rook has died.") of those who died this tick.
static func tick(ship, dt: float) -> Array:
	var lines := []
	var limit := bleed_out_s()
	var dying := []
	for m in ship.crew:
		if not m.is_down():
			m.down_t = 0.0
		elif not m.is_player and not _saved(ship, m):
			m.down_t += dt
			if m.down_t >= limit:
				dying.append(m)
	for m in dying:
		_die(ship, m)
		lines.append("%s has died." % m.name)
	return lines


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
	ship.crew.erase(m)
	ship.dead_crew.append(m.name)
	for uid in ship.manned.keys():
		if ship.manned[uid] == m.name:
			ship.manned.erase(uid)
	for c in ship.crew:
		if str(c.job.get("who", "")) == m.name:
			c.job = {}
			c.path.clear()
	m.job = {}
	m.path.clear()
